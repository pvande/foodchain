$foodchain_depfile = caller.first.rpartition(":").first

class Downloader
  def initialize(url, params, headers, &block)
    params = params.compact.map { |k, v| "#{k}=#{v}" }.join("&")
    @url = "#{url}?#{params}".delete_suffix("?")
    @headers = headers
    @result = nil
    @handler = block
  end

  def tick
    @result = $gtk.http_get(@url, @headers) if @result.nil?
    return unless @result[:complete]

    code = @result[:http_response_code]
    case code
    when 200
      @handler.call(@result)
    when 304
      $gtk.log_info "#{@url} is up-to-date.", "Foodchain"
    else
      $gtk.log_error "#{@url} returned status code #{code}", "Foodchain"
    end

    return @result
  end
end

class Dependency
  def update_lock(result)
    $state.locks[key] = result.dig(:response_headers, "Etag")
    $state.update_locks = true
  end
end

class Dependency::URL < Dependency
  def initialize(url, destination)
    @url = url
    @destination = destination
    @downloader = nil
  end

  def key
    @url
  end

  def tick
    if @downloader.nil?
      headers = ["If-None-Match: #{$state.locks[key]}"]
      @downloader = Downloader.new(@url, {}, headers) do |result|
        update_lock(result)
        $gtk.write_file(destination, result[:response_data])
      end
    end

    return if @downloader.tick.nil?
    $state.deps.delete(self)
  end
end

class Dependency::GitHub < Dependency
  ACCEPT_HEADER = "Accept: application/vnd.github.raw+json"

  def initialize(owner, repo, path, ref: nil, destination: nil)
    @owner = owner
    @repo = repo
    @path = path
    @ref = ref
    @url = "https://api.github.com/repos/#{owner}/#{repo}/contents/#{path}"
    @destination = destination || "vendor/#{id}"
    @queue = nil
  end

  def key
    "github://#{id}"
  end

  def id
    "#{@owner}/#{@repo}/#{@path}"
  end

  def tick
    if @queue.nil?
      @queue = []
      headers = [ ACCEPT_HEADER, "If-None-Match: #{$state.locks[key]}" ]

      job = Downloader.new(@url, { ref: @ref }, headers) do |result|
        update_lock(result)
        handle_response(@url, result, @destination)
        @queue.delete(job)
      end

      @queue << job
    end

    @queue.each(&:tick)
    return unless @queue.empty?

    $state.deps.delete(self)
  end

  def handle_response(url, result, destination)
    headers, body = result.values_at(:response_headers, :response_data)

    # If we got an "application/json" response, GitHub isn't sending us the raw
    # file contents. This happens when requesting a directory or other special
    # type of object.
    if headers["Content-Type"].start_with?("application/json")
      response = $gtk.parse_json(body)

      # For directory responses, GitHub sends an array of objects; symlinks and
      # submodules come back as hashes.
      if response.is_an?(Array)
        download_directory(response)
      else
        $gtk.log_error "Could not process the response from #{url}", "Foodchain"
      end
    else
      $gtk.write_file(destination, body)
    end
  end

  def download_directory(response)
    jobs = response.map! do |obj|
      next unless obj["type"] == "file" || obj["type"] == "dir"
      job = Downloader.new(obj["url"], {}, [ACCEPT_HEADER]) do |result|
        destination = "#{@destination}/#{obj["path"].delete_prefix(@path)}"

        handle_response(obj["url"], result, destination)
        @queue.delete(job)
      end
    end

    @queue += jobs.compact
  end
end

def url(url, destination)
  $state.deps << Dependency::URL.new(url, destination)
end

def github(owner, repo, file, ref: nil, destination: nil)
  $state.deps << Dependency::GitHub.new(
    owner,
    repo,
    file,
    ref: ref,
    destination: destination,
  )
end

def foodchain_init!
  $gtk.log_info "Verifying dependencies…", "Foodchain"

  contents = $gtk.read_file($foodchain_depfile)
  config, _, locks = contents.partition("__END__\n")
  config.rstrip!

  locks = locks.lines.map!(&:chomp)
  locks.reject!(&:empty?)
  locks.reject! { |x| x.start_with?("#") }
  locks = locks.to_h { |line| line.split("\t") }

  $state.foodchain_depfile = $foodchain_depfile
  $state.config = config
  $state.locks = locks.slice(*$state.deps.map(&:key).sort)
  $state.update_locks = (locks.size != $state.locks.size)
end

def $gtk.tick_core
  @is_inside_tick = true

  foodchain_init! if Kernel.global_tick_count.zero?

  $state.deps.each(&:tick)

  if $state.deps.empty?
    update_locks! if $state.update_locks

    $gtk.log_info "All done!", "Foodchain"
    $gtk.request_quit
  end

  @is_inside_tick = false
end

def update_locks!
  $gtk.log_info "Updating locks…", "Foodchain"
  contents = [
    $state.config,
    ["", "__END__", ""],
    $state.locks.to_a.map { |pair| pair.join("\t") },
  ]

  $gtk.write_file($foodchain_depfile, contents.flatten.join("\n"))
end

$state.deps = []
