# Foodchain

## Configure

``` ruby
# mygame/dependencies.rb
require "lib/foodchain"

# Easily download individual files from GitHub…
github :pvande, :dragonborn, "dragonborn.rb"

# … including from specific branches, tags, or commits …
github :xenobrain, :rubycolors, "color.rb", ref: "bab319b6553327f545d8760fe4d17d92d0d85845"

# … reading from and/or writing to specific paths …
github :mruby, :mruby, "mrbgems/mruby-enumerator/mrblib/enumerator.rb", destination: "vendor/enumerator.rb"

# … including entire directories!
github :mruby, :mruby, "mrbgems/mruby-set/mrblib", destination: "vendor"

# Arbitrary URLs are also supported.
url "https://gitlab.com/dragon-ruby/fang/-/raw/main/from_now.rb", destination: "vendor/fang/from_now.rb"
```

## Run

``` shell
./dragonruby mygame --eval dependencies.rb

# Write mygame/vendor/pvande/dragonborn/dragonborn.rb
# Write mygame/vendor/xenobrain/rubycolors/color.rb
# Write mygame/vendor/enumerator.rb
# Write mygame/vendor/set.rb
# Write mygame/vendor/fang/from_now.rb
# Update mygame/dependencies.rb
```

## Verify

``` shell
ls -R mygame/vendor | cat
# enumerator.rb
# fang
# pvande
# set.rb
# xenobrain
#
# game/vendor/fang:
# from_now.rb
#
# game/vendor/pvande:
# dragonborn
#
# game/vendor/pvande/dragonborn:
# dragonborn.rb
#
# game/vendor/xenobrain:
# rubycolors
#
# game/vendor/xenobrain/rubycolors:
# color.rb

cat mygame/dependencies.rb
# require "lib/foodchain"
#
# # Easily download individual files from GitHub…
# github :pvande, :dragonborn, "dragonborn.rb"
#
# # … including from specific branches, tags, or commits …
# github :xenobrain, :rubycolors, "color.rb", ref: "bab319b6553327f545d8760fe4d17d92d0d85845"
#
# # … reading from and/or writing to specific paths …
# github :mruby, :mruby, "mrbgems/mruby-enumerator/mrblib/enumerator.rb", destination: "vendor/enumerator.rb"
#
# # … including entire directories!
# github :mruby, :mruby, "mrbgems/mruby-set/mrblib", destination: "vendor"
#
# # Arbitrary URLs are also supported.
# url "https://gitlab.com/dragon-ruby/fang/-/raw/main/from_now.rb", destination: "vendor/fang/from_now.rb"
#
# __END__
#
# # The lines below indicate the versions of your installed dependencies.
# # To upgrade dependencies, simply remove the corresponding lines below.
#
# https://gitlab.com/dragon-ruby/fang/-/raw/main/from_now.rb	"84b0d51f5c2adba984f96d59a11e7ae4"
# github://mruby/mruby/mrbgems/mruby-set/mrblib	W/"2c437816fe3ac100234eb425ca3e34b95036e9ea"
# github://pvande/dragonborn/dragonborn.rb	"5166a35e916413f6a3f27ec6d4d651c854047fa7"
# github://xenobrain/rubycolors/color.rb	"27bac6656dcd5dde09e35c0ca00c260f88eb36ed"
# github://mruby/mruby/mrbgems/mruby-enumerator/mrblib/enumerator.rb	"44d84865a448ed5f1b0f285f7cd072daeb7d82f3"
```
