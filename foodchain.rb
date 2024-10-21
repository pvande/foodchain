# Handles the mechanics of performing an HTTP GET request. Calls the block iff
# the request was successful; error handling is hardcoded for this application.
class Downloader
  # Creates a new Downloader, responsible for making a single HTTP request.
  #
  # @param url [String] The URL to fetch.
  # @param headers [Array] An array of HTTP header strings to include.
  # @yield [Hash] The result of the HTTP request.
  def initialize(url, headers, &block)
    unless block_given?
      raise ArgumentError, "Downloader cannot be constructed without a block"
    end

    @url = url
    @headers = headers
    @handler = block
    @result = $gtk.http_get(url, headers)
    @result.merge!(url: url, request_headers: headers)
  end

  # Calls the handler the result once the request has been completed.
  def tick
    @handler.call(@result) if @result[:complete]
  end

  # @returns [Boolean] Has this request completed?
  def complete?
    @result[:complete]
  end
end

# Represents an dependency; look to subclasses for specific implementations.
# @abstract
class Dependency
  # Intitializes a new Dependency with an empty download queue.
  def initialize
    @download_queue = []
  end

  # Identifies this dependency in the lock table.
  # @abstract
  def key
    raise NotImplementedError, "Dependency subclasses must implement #key."
  end

  # Configures the initial download for this dependency.
  # @abstract
  def boot
    raise NotImplementedError, "Dependency subclasses must implement #boot."
  end

  # Causes each download in the queue to tick, discarding any finished requests.
  def tick
    @download_queue.each(&:tick).reject!(&:complete?)
  end

  # Creates and enqueues a new download. Dispatches to the passed block on
  # successful requests.
  # @see Downloader#initialize
  def download(url, headers, &block)
    @download_queue << Downloader.new(url, headers) do |result|
      case (code = result[:http_response_code])
      when 200
        yield result
      when 304
        $gtk.log_info "#{key} is up-to-date.", "Foodchain"
      else
        $gtk.log_error "GET #{url} returned status code #{code}", "Foodchain"
      end
    end
  end

  # Records a new lock version for this dependency.
  #
  # We're leveraging the `Etag` cache key as our lock version by convention,
  # since it's an identifier of what the server believes identifies this version
  # of the content, and can be used with conditional HTTP requests.
  #
  # @param result [Hash] The response from a successful HTTP request.
  def update_lock_version(result)
    etag = result.dig(:response_headers, "Etag")
    if $state.locks[key] && $state.locks[key] != etag
      $state.outdated << key
    else
      $state.locks[key] = etag
      $state.update_lock_versions = true
    end
  end

  # @return [Boolean] Has this dependency been resolved?
  def complete?
    @download_queue.empty?
  end
end

# Represents a direct dependency on a URL.
class Dependency::URL < Dependency
  # Creates a new `Dependency` on a specific URL.
  #
  # @param url [String] The resource to be downloaded.
  # @param destination [String] The game-local file path for the download.
  def initialize(url, destination:)
    super()
    @url = url
    @destination = destination
  end

  # {include:Dependency#key}
  def key
    @url
  end

  # {include:Dependency#boot}
  def boot
    download(@url, ["If-None-Match: #{$state.locks[key]}"]) do |result|
      update_lock_version(result)
      $gtk.write_file(@destination, result[:response_data])
    end
  end
end

# Represents a dependency on a resource hosted by GitHub.
class Dependency::GitHub < Dependency
  ACCEPT_HEADER = "Accept: application/vnd.github.raw+json"

  # Creates a new `Dependency` on a path within a specific GitHub repository.
  #
  # @param owner [#to_s] The repository's owner.
  # @param repo [#to_s] The repository's name.
  # @param path [#to_s] The repository-relative path do be downloaded. This may
  #        be either a single file or a directory (which will be downloaded
  #        recursively into `destination`).
  # @param ref [#to_s, nil] The git "ref" to use. Can identify a branch, a tag,
  #        or a specific commit SHA. If omitted, GitHub will use the HEAD of the
  #        default branch.
  # @param destination [String, nil] The game-local file path for the download.
  #        If `path` refers to a file, then `destination` will be treated as the
  #        path in which to save that file's contents; if `path` refers to a
  #        directory, then the files within that directory will be saved into a
  #        local directory named `destination`.
  def initialize(owner, repo, path, ref: nil, destination: nil)
    super()

    @owner = owner
    @repo = repo
    @path = path
    @ref = ref || ""

    @url = "https://api.github.com/repos/#{owner}/#{repo}/contents/#{path}"
    @destination = destination || "vendor/#{owner}/#{repo}/#{path}"
  end

  # {include:Dependency#key}
  def key
    "github:#{@owner}/#{@repo}/#{@path}"
  end

  # {include:Dependency#boot}
  def boot
    url = (@ref.empty? ? @url : "#{@url}?ref=#{@ref}")
    headers = [ ACCEPT_HEADER, "If-None-Match: #{$state.locks[key]}" ]

    download(url, headers) do |result|
      update_lock_version(result)
      process(result, @destination)
    end
  end

  # Handles a successful API response from Github.
  #
  # In practice, there are three types of responses we can expect to recieve
  # from the API endpoint we're querying:
  # * Responses for *regular file* requests will have a Content-Type that
  #   matches our `Accept` header, and will have a body that contains the file's
  #   contents.
  # * Responses for *directory* requests will have a Content-Type of
  #   `application/json`, and will contain a JSON array of hashes describing the
  #   directory's contents.
  # * Responses for *other* object types (including symlinks and submodules)
  #   will have a Content-Type of `application/json`, and will contain a JSON
  #   hash describing that object.
  #
  # We make no effort to process anything but files and directories.
  #
  # @param result [Hash] The result of the HTTP query.
  # @param destination [String] The game-relative file path for this result.
  def process(result, destination)
    headers, body = result.values_at(:response_headers, :response_data)

    # If we got an "application/json" response, GitHub isn't sending us the raw
    # file contents. This happens when requesting a directory or other special
    # type of object.
    if headers["Content-Type"].start_with?("application/json")
      response = $gtk.parse_json(body)

      # For directory responses, GitHub sends an array of objects; symlinks and
      # submodules come back as hashes.
      if response.is_a?(Array)
        response.each do |obj|
          type, url, path = obj.values_at("type", "url", "path")
          next unless %w[ file dir ].include?(type)

          # @TODO We currently don't store lock versions for recursive queries.
          #       This is based on the assumption that GitHub would return a new
          #       Etag value if the directory or any of its descendants were
          #       changed. We should validate this assumption, since it's
          #       possible that GitHub may only change based on the response
          #       content (which is inherently shallow).
          download(url, [ACCEPT_HEADER]) do |result|
            result.merge!(url: url)
            destination = "#{@destination}/#{path.delete_prefix(@path)}"
            process(result, destination)
          end
        end
      else
        message = "Could not process the response from #{result[:url]}"
        $gtk.log_error message, "Foodchain"
      end
    else
      $gtk.write_file(destination, body)
    end
  end
end

# Records a dependency on a specific URL.
# @param url [String] The resource to be downloaded.
# @param destination [String] The game-local file path for the download.
def url(url, destination:)
  $state.deps << Dependency::URL.new(url, destination: destination)
end

# Creates a new `Dependency` on a path within a specific GitHub repository.
#
# @param owner [#to_s] The repository's owner.
# @param repo [#to_s] The repository's name.
# @param path [#to_s] The repository-relative path do be downloaded. This may
#        be either a single file or a directory (which will be downloaded
#        recursively into `destination`).
# @param ref [#to_s, nil] The git "ref" to use. Can identify a branch, a tag,
#        or a specific commit SHA. If omitted, GitHub will use the HEAD of the
#        default branch.
# @param destination [String, nil] The game-local file path for the download.
#        If `path` refers to a file, then `destination` will be treated as the
#        path in which to save that file's contents; if `path` refers to a
#        directory, then the files within that directory will be saved into a
#        local directory named `destination`.
#        Defaults to "vendor/$owner/$repo/$path".
def github(owner, repo, file, ref: nil, destination: nil)
  $state.deps << Dependency::GitHub.new(
    owner,
    repo,
    file,
    ref: ref,
    destination: destination,
  )
end

HELP_FLAGS = %i[ help noop no-op dryrun dry-run ]
UPDATE_FLAGS = %i[ update upgrade overwrite ]
# Implements the basic fetch loop.
#
# @NOTE This hooks into the `GTK::Runtime` at a fairly low level, specifically
#       because `--eval` will run this *after* loading `app/main.rb` — if the
#       game has itself patched `GTK::Runtime` in this way, a simple global
#       `tick` method is never going to be executed.
def $gtk.tick_core
  @is_inside_tick = true

  unless $gtk.cli_arguments.key?(:eval)
    $gtk.log_error "\n\n" + <<~TEXT, "Foodchain"
      Foodchain is not intended to be required in your game's code.
      Please move your dependencies into a separate file, and run:

        #{$gtk.argv} --eval <your-dependency-file.rb>
    TEXT
    return $gtk.request_quit
  end

  if ($gtk.cli_arguments.keys & HELP_FLAGS).any?
    $gtk.log_debug "\n\n" + <<~HELP, "Foodchain"
      Dependency management by Foodchain
      https://github.com/pvande/foodchain

      Installs the dependencies described in #{$gtk.cli_arguments[:eval]}.

      Options:
        --update [dependency-key ...]
          Updates the identified dependencies with their current versions. If no
          dependencies are identified, all non-current dependencies are updated.
        --help
          Displays this help message.
    HELP
    return $gtk.request_quit
  end

  if Kernel.global_tick_count.zero?
    contents = $gtk.read_file($state.depfile)
    config, _, locks = contents.partition("__END__\n")
    config.rstrip!

    locks = locks.lines.map!(&:chomp)
    locks.reject!(&:empty?)
    locks.reject! { |x| x.start_with?("#") }
    locks = locks.to_h { |line| line.split("\t") }

    $state.config = config
    $state.locks = locks.slice(*$state.deps.map(&:key).sort)
    $state.update_lock_versions = (locks.size != $state.locks.size)
    $state.outdated = []

    action = "Installing"
    upgrades = nil
    if ($gtk.cli_arguments.keys & UPDATE_FLAGS).any?
      action = "Upgrading"
      upgrades = $gtk.cli_arguments.values_at(*UPDATE_FLAGS)
      upgrades.map! { |opt| Array(opt) }.flatten!

      if upgrades.empty?
        $state.locks.clear
      else
        unknown = upgrades - $state.deps.map(&:key)
        if unknown.any?
          $gtk.log_error "\n\n" + <<~TEXT, "Foodchain"
            The following dependencies are unknown:
            #{unknown.map! { |x| "  * " + x }.join("\n")}

            Please pass the dependency keys from #{$gtk.cli_arguments[:eval]},
            or pass no argument to upgrade all dependencies.
          TEXT
          return $gtk.request_quit
        end

        $state.locks = $state.locks.except(*upgrades)
      end
    end

    $gtk.log_info "#{action} dependencies…", "Foodchain"
    $state.deps.each(&:boot)
  end

  $state.deps.each(&:tick).reject!(&:complete?)
  return unless $state.deps.empty?

  if $state.update_lock_versions
    $gtk.log_info "Updating locks…", "Foodchain"
    contents = [
      $state.config,
      "",
      "__END__",
      "",
      "# The lines below pin the versions of your installed dependencies.",
      "# Removing or changing these lines may result in those dependencies",
      "# being overwritten on your next installation.",
      "",
      $state.locks.to_a.map { |pair| pair.join("\t") }.sort,
      "",
    ]

    $gtk.write_file($state.depfile, contents.flatten.join("\n"))
  end

  if $state.outdated.any?
    if $state.outdated.one?
      $gtk.log_debug "\n\n" + <<~HELP, "Foodchain"
        An update is available for #{$state.outdated.first}

        Please run this again with the `--update` option to update.
      HELP
    else
      $gtk.log_debug "\n\n" + <<~HELP, "Foodchain"
        The following dependencies have updates available:
        #{$state.outdated.map! { |x| "  * " + x }.join("\n")}

        Please run this again with the `--update` option to update all these
        depenencies, or run with `--update [dependency-key]` to update single
        dependencies one at a time.
      HELP
    end
  end

  $gtk.log_info "All done!", "Foodchain"
  $gtk.request_quit
ensure
  @is_inside_tick = false
end

$state.depfile = caller.first.rpartition(":").first
$state.deps = []
