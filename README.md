# Foodchain

Foodchain is a single-file library to help you document and install your
DragonRuby game's dependencies.

## Rationale

Installing dependencies in DragonRuby isn't particularly hard — the majority of
library code available for the framework is available as single-file libraries
that can be downloaded, required, and forgotten. DragonRuby GTK even includes
the `download_stb_rb` function to facilitate downloading these libraries, which
is great … for as far as it goes.

On the other extreme you have tools like RubyGems, which are a publishing
platform for code that's production ready, a tool for putting that code (and any
code that it depends on) into a centralized location, and a runtime library for
ensuring that code in that centralized location can be loaded. Built on top of
that are tools like Bundler, which manage the specific versions of dependencies
required by your application (in a way that's repeatable across machines), and
which isolate your appilication from the *other* centrally installed libraries.
The caveat for DragonRuby developers is that these tools do not (and cannot)
work with the DragonRuby runtime, and most of the libraries that are published
as RubyGems won't work anyway.

Foodchain intends to sit in the gap between those two extremes.

* Fully Decentralized
  * Pull what you want from wherever it lives.
* Git-Aware
  * Pin your dependencies to a particular branch, tag, or commit.
* Documentation
  * Borrow code with the confidence that you'll remember it came from.
* No External Dependencies
  * Everything runs inside the DragonRuby runtime you already have.

## Usage

Start by saving [foodchain.rb] into your game's source tree. DragonRuby even
provides [a built-in tool][download_stb] for doing this, which you can run from
your game's console:

```ruby
# Downloads to pvande/foodchain/foodchain.rb
$gtk.download_stb_rb "pvande", "foodchain", "foodchain.rb"

# OR

# Downloads to wherever/you/want.rb
url = "https://raw.githubusercontent.com/pvande/foodchain/main/foodchain.rb"
$gtk.download_stb_rb_raw url, "wherever/you/want.rb"
```

Next, you'll create a dependency manifest — a file that lists the dependencies
you want Foodchain to install. Conventionally, we recommend using a file named
`dependencies.rb`, living in the root directory of your game.

Require Foodchain inside your dependency manifest file.

```ruby
# mygame/dependencies.rb
require "pvande/foodchain/foodchain"
```

In this file, you'll [document your game's dependencies](#configuration).

When you're ready to install, just run that dependency manifest.

```shell
./dragonruby mygame --eval dependencies.rb
```

### What's `__END__`?

After successfully installing your dependencies, Foodchain will record a few
details about the process at the end of your dependency manifest. This isn't
cause for alarm: Foodchain will use this to detect when there's an update
available for one of your dependencies, and notify you.

Foodchain will never automatically overwrite any of your installed dependencies,
so you can run it and rerun it as often as you like. When you're ready to test
an update, you can rerun your dependency manifest with the `--update` flag, and
the file(s) will be downloaded fresh.

## Configuration

Foodchain dependencies currently come in the following flavors:

### github [owner], [repo], [path], ref: [ref?], destination: [destination?]

GitHub dependencies are fetched based on the `path` within the `owner`'s fork of
the named `repo`.

A specific `ref` may be specified to follow a particular Git branch, or pin to a
particular Git tag or commit. When omitted, this will fetch from the
repositories default branch (usually `main` or `master`).

Downloaded dependencies will then be saved into the specified `destination`.
When omitted, this will default to `vendor/$owner/$repo/$path`.

The `path` indicated can specify either a path to a regular file within the
repository, or the path to a *directory*. In the latter case, all files from
that directory in the repository will be downloaded recursively and stored in a
directory named `destination`.

### url [url], destination: [destination]

URL dependencies are handled as a simple HTTP fetch — the contents of the remote
`url` are saved into the file named by `destination`. This is a useful option
when a more specific dependency type is not available.

## Example Manifest

``` ruby
# mygame/dependencies.rb

require "lib/foodchain"

# Download the version of `pvande/dragonborn/dragonborn.rb` from `main`.
# Creates `vendor/pvande/dragonborn/dragonborn.rb`.
github :pvande, :dragonborn, "dragonborn.rb"

# Download the version of `xenobrain/rubycolors/color.rb` from `bab319b65`.
# Creates `vendor/xenobrain/rubycolors/color.rb`.
github :xenobrain, :rubycolors, "color.rb", ref: "bab319b65"

# Download the version of `mruby/mruby/mrbgems/mruby-set/mrblib/set.rb` from `main`.
# Creates `vendor/set.rb`.
github :mruby, :mruby, "mrbgems/mruby-set/mrblib/set.rb", destination: "vendor/set.rb"

# Download the version of `danhealy/dragonruby-zif/lib` from `main`.
# Creates `vendor/zif`.
github :danhealy, "dragonruby-zif", "lib", destination: "vendor/zif"

# Downloads the URL into `vendor/fang/from_now.rb`.
url "https://gitlab.com/dragon-ruby/fang/-/raw/main/from_now.rb", destination: "vendor/fang/from_now.rb"
```

[foodchain.rb]: https://raw.githubusercontent.com/pvande/foodchain/main/foodchain.rb
[download_stb]: https://docs.dragonruby.org/#/api/runtime?id=download_stb_rb_raw
