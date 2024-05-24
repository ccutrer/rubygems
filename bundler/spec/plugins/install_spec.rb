# frozen_string_literal: true

RSpec.describe "bundler plugin install" do
  before do
    build_repo2 do
      build_plugin "foo"
      build_plugin "kung-foo"
    end
  end

  it "shows proper message when gem in not found in the source" do
    bundle "plugin install no-foo --source #{file_uri_for(gem_repo1)}", raise_on_error: false

    expect(err).to include("Could not find")
    plugin_should_not_be_installed("no-foo")
  end

  it "installs from rubygems source" do
    bundle "plugin install foo --source #{file_uri_for(gem_repo2)}"

    expect(out).to include("Installed plugin foo")
    plugin_should_be_installed("foo")
  end

  it "installs from rubygems source in frozen mode" do
    bundle "plugin install foo --source #{file_uri_for(gem_repo2)}", env: { "BUNDLE_DEPLOYMENT" => "true" }

    expect(out).to include("Installed plugin foo")
    plugin_should_be_installed("foo")
  end

  it "installs from sources configured as Gem.sources without any flags" do
    bundle "plugin install foo", env: { "BUNDLER_SPEC_GEM_SOURCES" => file_uri_for(gem_repo2).to_s }

    expect(out).to include("Installed plugin foo")
    plugin_should_be_installed("foo")
  end

  it "shows help when --help flag is given" do
    bundle "plugin install --help"

    # The help message defined in ../../lib/bundler/man/bundle-plugin.1.ronn will be output.
    expect(out).to include("You can install, uninstall, and list plugin(s)")
  end

  context "plugin is already installed" do
    before do
      bundle "plugin install foo --source #{file_uri_for(gem_repo2)}"
    end

    it "doesn't install plugin again" do
      bundle "plugin install foo --source #{file_uri_for(gem_repo2)}"
      expect(out).not_to include("Installing plugin foo")
      expect(out).not_to include("Installed plugin foo")
    end
  end

  it "installs multiple plugins" do
    bundle "plugin install foo kung-foo --source #{file_uri_for(gem_repo2)}"

    expect(out).to include("Installed plugin foo")
    expect(out).to include("Installed plugin kung-foo")

    plugin_should_be_installed("foo", "kung-foo")
  end

  it "uses the same version for multiple plugins" do
    update_repo2 do
      build_plugin "foo", "1.1"
      build_plugin "kung-foo", "1.1"
    end

    bundle "plugin install foo kung-foo --version '1.0' --source #{file_uri_for(gem_repo2)}"

    expect(out).to include("Installing foo 1.0")
    expect(out).to include("Installing kung-foo 1.0")
    plugin_should_be_installed("foo", "kung-foo")
  end

  it "installs the latest version if not installed" do
    update_repo2 do
      build_plugin "foo", "1.1"
    end

    bundle "plugin install foo --version 1.0 --source #{file_uri_for(gem_repo2)} --verbose"
    expect(out).to include("Installing foo 1.0")

    bundle "plugin install foo --source #{file_uri_for(gem_repo2)} --verbose"
    expect(out).to include("Installing foo 1.1")

    bundle "plugin install foo --source #{file_uri_for(gem_repo2)} --verbose"
    expect(out).to include("Using foo 1.1")
  end

  it "raises an error when when --branch specified" do
    bundle "plugin install foo --branch main --source #{file_uri_for(gem_repo2)}", raise_on_error: false

    expect(out).not_to include("Installed plugin foo")

    expect(err).to include("--branch can only be used with git sources")
  end

  it "raises an error when --ref specified" do
    bundle "plugin install foo --ref v1.2.3 --source #{file_uri_for(gem_repo2)}", raise_on_error: false

    expect(err).to include("--ref can only be used with git sources")
  end

  it "raises error when both --branch and --ref options are specified" do
    bundle "plugin install foo --source #{file_uri_for(gem_repo2)} --branch main --ref v1.2.3", raise_on_error: false

    expect(out).not_to include("Installed plugin foo")

    expect(err).to include("You cannot specify `--branch` and `--ref` at the same time.")
  end

  it "works with different load paths" do
    build_repo2 do
      build_plugin "testing" do |s|
        s.write "plugins.rb", <<-RUBY
          require "fubar"
          class Test < Bundler::Plugin::API
            command "check2"

            def exec(command, args)
              puts "mate"
            end
          end
        RUBY
        s.require_paths = %w[lib src]
        s.write("src/fubar.rb")
      end
    end
    bundle "plugin install testing --source #{file_uri_for(gem_repo2)}"

    bundle "check2", "no-color" => false
    expect(out).to eq("mate")
  end

  context "malformatted plugin" do
    it "fails when plugins.rb is missing" do
      update_repo2 do
        build_plugin "foo", "1.1"
        build_plugin "kung-foo", "1.1"
      end

      bundle "plugin install foo kung-foo --version '1.0' --source #{file_uri_for(gem_repo2)}"

      expect(out).to include("Installing foo 1.0")
      expect(out).to include("Installing kung-foo 1.0")
      plugin_should_be_installed("foo", "kung-foo")

      build_repo2 do
        build_gem "charlie"
      end

      bundle "plugin install charlie --source #{file_uri_for(gem_repo2)}", raise_on_error: false

      expect(err).to include("Failed to install plugin `charlie`, due to Bundler::Plugin::MalformattedPlugin (plugins.rb was not found in the plugin.)")

      expect(global_plugin_gem("charlie-1.0")).not_to be_directory

      plugin_should_be_installed("foo", "kung-foo")
      plugin_should_not_be_installed("charlie")
    end

    it "fails when plugins.rb throws exception on load" do
      build_repo2 do
        build_plugin "chaplin" do |s|
          s.write "plugins.rb", <<-RUBY
            raise "I got you man"
          RUBY
        end
      end

      bundle "plugin install chaplin --source #{file_uri_for(gem_repo2)}", raise_on_error: false

      expect(global_plugin_gem("chaplin-1.0")).not_to be_directory

      plugin_should_not_be_installed("chaplin")
    end
  end

  context "git plugins" do
    it "installs form a git source" do
      build_git "foo" do |s|
        s.write "plugins.rb"
      end

      bundle "plugin install foo --git #{file_uri_for(lib_path("foo-1.0"))}"

      expect(out).to include("Installed plugin foo")
      plugin_should_be_installed("foo")
    end

    it "installs form a local git source" do
      build_git "foo" do |s|
        s.write "plugins.rb"
      end

      bundle "plugin install foo --git #{lib_path("foo-1.0")}"

      expect(out).to include("Installed plugin foo")
      plugin_should_be_installed("foo")
    end

    it "raises an error when both git and local git sources are specified", bundler: "< 3" do
      bundle "plugin install foo --git /phony/path/project --local_git git@gitphony.com:/repo/project", raise_on_error: false

      expect(exitstatus).not_to eq(0)
      expect(err).to eq("Remote and local plugin git sources can't be both specified")
    end
  end

  context "path plugins" do
    it "installs from a path source" do
      build_lib "path_plugin" do |s|
        s.write "plugins.rb"
      end
      bundle "plugin install path_plugin --path #{lib_path("path_plugin-1.0")}"

      expect(out).to include("Installed plugin path_plugin")
      plugin_should_be_installed("path_plugin")
    end

    it "installs from a relative path source" do
      build_lib "path_plugin" do |s|
        s.write "plugins.rb"
      end
      path = lib_path("path_plugin-1.0").relative_path_from(bundled_app)
      bundle "plugin install path_plugin --path #{path}"

      expect(out).to include("Installed plugin path_plugin")
      plugin_should_be_installed("path_plugin")
    end

    it "installs from a relative path source when inside an app" do
      allow(Bundler::SharedHelpers).to receive(:find_gemfile).and_return(bundled_app_gemfile)
      gemfile ""

      build_lib "ga-plugin" do |s|
        s.write "plugins.rb"
      end

      path = lib_path("ga-plugin-1.0").relative_path_from(bundled_app)
      bundle "plugin install ga-plugin --path #{path}"

      plugin_should_be_installed("ga-plugin")
      expect(local_plugin_gem("foo-1.0")).not_to be_directory
    end
  end

  context "Gemfile eval" do
    before do
      allow(Bundler::SharedHelpers).to receive(:find_gemfile).and_return(bundled_app_gemfile)
    end

    it "installs plugins listed in gemfile" do
      gemfile <<-G
        source '#{file_uri_for(gem_repo2)}'
        plugin 'foo'
        gem 'rack', "1.0.0"
      G

      bundle "install"

      expect(out).to include("Installed plugin foo")

      expect(out).to include("Bundle complete!")

      expect(the_bundle).to include_gems("rack 1.0.0")
      plugin_should_be_installed("foo")
    end

    it "accepts plugin version" do
      update_repo2 do
        build_plugin "foo", "1.1.0"
      end

      gemfile <<-G
        source '#{file_uri_for(gem_repo2)}'
        plugin 'foo', "1.0"
      G

      bundle "install"

      expect(out).to include("Installing foo 1.0")

      plugin_should_be_installed("foo")

      expect(out).to include("Bundle complete!")
    end

    it "installs plugins in included groups" do
      gemfile <<-G
        source '#{file_uri_for(gem_repo2)}'
        group :development do
          plugin 'foo'
        end
        gem 'rack', "1.0.0"
      G

      bundle "install"

      expect(out).to include("Installed plugin foo")

      expect(out).to include("Bundle complete!")

      expect(the_bundle).to include_gems("rack 1.0.0")
      plugin_should_be_installed("foo")
    end

    it "does not install plugins in excluded groups" do
      gemfile <<-G
        source '#{file_uri_for(gem_repo2)}'
        group :development do
          plugin 'foo'
        end
        gem 'rack', "1.0.0"
      G

      bundle "config set --local without development"
      bundle "install"

      expect(out).not_to include("Installed plugin foo")

      expect(out).to include("Bundle complete!")

      expect(the_bundle).to include_gems("rack 1.0.0")
      plugin_should_not_be_installed("foo")
    end

    it "upgrade plugins version listed in gemfile" do
      update_repo2 do
        build_plugin "foo", "1.4.0"
        build_plugin "foo", "1.5.0"
      end

      gemfile <<-G
        source '#{file_uri_for(gem_repo2)}'
        plugin 'foo', "1.4.0"
        gem 'rack', "1.0.0"
      G

      bundle "install"

      expect(out).to include("Installing foo 1.4.0")
      expect(out).to include("Installed plugin foo")
      expect(out).to include("Bundle complete!")

      expect(the_bundle).to include_gems("rack 1.0.0")
      plugin_should_be_installed_with_version("foo", "1.4.0")

      gemfile <<-G
        source '#{file_uri_for(gem_repo2)}'
        plugin 'foo', "1.5.0"
        gem 'rack', "1.0.0"
      G

      bundle "install"

      expect(out).to include("Installing foo 1.5.0")
      expect(out).to include("Bundle complete!")

      expect(the_bundle).to include_gems("rack 1.0.0")
      plugin_should_be_installed_with_version("foo", "1.5.0")
    end

    it "downgrade plugins version listed in gemfile" do
      update_repo2 do
        build_plugin "foo", "1.4.0"
        build_plugin "foo", "1.5.0"
      end

      gemfile <<-G
        source '#{file_uri_for(gem_repo2)}'
        plugin 'foo', "1.5.0"
        gem 'rack', "1.0.0"
      G

      bundle "install"

      expect(out).to include("Installing foo 1.5.0")
      expect(out).to include("Installed plugin foo")
      expect(out).to include("Bundle complete!")

      expect(the_bundle).to include_gems("rack 1.0.0")
      plugin_should_be_installed_with_version("foo", "1.5.0")

      gemfile <<-G
        source '#{file_uri_for(gem_repo2)}'
        plugin 'foo', "1.4.0"
        gem 'rack', "1.0.0"
      G

      bundle "install"

      expect(out).to include("Installing foo 1.4.0")
      expect(out).to include("Bundle complete!")

      expect(the_bundle).to include_gems("rack 1.0.0")
      plugin_should_be_installed_with_version("foo", "1.4.0")
    end

    it "install only plugins not installed yet listed in gemfile" do
      gemfile <<-G
        source '#{file_uri_for(gem_repo2)}'
        plugin 'foo'
        gem 'rack', "1.0.0"
      G

      2.times { bundle "install" }

      expect(out).to_not include("Fetching gem metadata")
      expect(out).to_not include("Fetching foo")
      expect(out).to_not include("Installed plugin foo")

      expect(out).to include("Bundle complete!")

      expect(the_bundle).to include_gems("rack 1.0.0")
      plugin_should_be_installed("foo")

      gemfile <<-G
        source '#{file_uri_for(gem_repo2)}'
        plugin 'foo'
        plugin 'kung-foo'
        gem 'rack', "1.0.0"
      G

      bundle "install"

      expect(out).to include("Installing kung-foo")
      expect(out).to include("Installed plugin kung-foo")

      expect(out).to_not include("Fetching foo")
      expect(out).to_not include("Installed plugin foo")

      expect(out).to include("Bundle complete!")

      expect(the_bundle).to include_gems("rack 1.0.0")
      plugin_should_be_installed("foo")
      plugin_should_be_installed("kung-foo")
    end

    it "accepts git sources" do
      build_git "ga-plugin" do |s|
        s.write "plugins.rb"
      end

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        plugin 'ga-plugin', :git => "#{lib_path("ga-plugin-1.0")}"
      G

      expect(out).to include("Installed plugin ga-plugin")
      plugin_should_be_installed("ga-plugin")
    end

    it "accepts path sources" do
      build_lib "ga-plugin" do |s|
        s.write "plugins.rb"
      end

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        plugin 'ga-plugin', :path => "#{lib_path("ga-plugin-1.0")}"
      G

      expect(out).to include("Installed plugin ga-plugin")
      plugin_should_be_installed("ga-plugin")
    end

    it "accepts relative path sources" do
      build_lib "ga-plugin" do |s|
        s.write "plugins.rb"
      end

      path = lib_path("ga-plugin-1.0").relative_path_from(bundled_app)
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        plugin 'ga-plugin', :path => "#{path}"
      G

      expect(out).to include("Installed plugin ga-plugin")
      plugin_should_be_installed("ga-plugin")
    end

    context "in deployment mode" do
      it "installs plugins" do
        install_gemfile <<-G
          source '#{file_uri_for(gem_repo2)}'
          gem 'rack', "1.0.0"
        G

        bundle "config set --local deployment true"
        install_gemfile <<-G
          source '#{file_uri_for(gem_repo2)}'
          plugin 'foo'
          gem 'rack', "1.0.0"
        G

        expect(out).to include("Installed plugin foo")

        expect(out).to include("Bundle complete!")

        expect(the_bundle).to include_gems("rack 1.0.0")
        plugin_should_be_installed("foo")
      end
    end

    it "fails bundle commands if plugins are not yet installed" do
      gemfile <<-G
        source '#{file_uri_for(gem_repo2)}'
        group :development do
          plugin 'foo'
        end

        source '#{file_uri_for(gem_repo1)}' do
          gem 'rake'
        end
      G

      plugin_should_not_be_installed("foo")

      bundle "check", raise_on_error: false
      expect(err).to include("Plugin foo (>= 0) is not installed")

      bundle "exec rake", raise_on_error: false
      expect(err).to include("Plugin foo (>= 0) is not installed")

      bundle "config set --local without development"
      bundle "install"
      bundle "config unset --local without"

      plugin_should_not_be_installed("foo")

      bundle "check", raise_on_error: false
      expect(err).to include("Plugin foo (>= 0) is not installed")

      bundle "exec rake", raise_on_error: false
      expect(err).to include("Plugin foo (>= 0) is not installed")

      plugin_should_not_be_installed("foo")

      bundle "install"
      plugin_should_be_installed("foo")

      bundle "check"
      bundle "exec rake -T", raise_on_error: false
      expect(err).not_to include("Plugin foo (>= 0) is not installed")
    end

    it "fails bundle commands gracefully when a plugin index reference is left dangling" do
      build_lib "ga-plugin" do |s|
        s.write "plugins.rb"
      end

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        plugin 'ga-plugin', :path => "#{lib_path("ga-plugin-1.0")}"
      G

      expect(out).to include("Installed plugin ga-plugin")
      plugin_should_be_installed("ga-plugin")

      FileUtils.rm_rf(lib_path("ga-plugin-1.0"))

      plugin_should_not_be_installed("ga-plugin")

      bundle "check", raise_on_error: false
      expect(err).to include("Plugin ga-plugin (>= 0) is not installed")
    end
  end

  context "inline gemfiles" do
    it "installs the listed plugins" do
      code = <<-RUBY
        require "bundler/inline"

        gemfile do
          source '#{file_uri_for(gem_repo2)}'
          plugin 'foo'
        end
      RUBY

      ruby code, env: { "BUNDLER_VERSION" => Bundler::VERSION }

      allow(Bundler::SharedHelpers).to receive(:find_gemfile).and_return(bundled_app_gemfile)
      plugin_should_be_installed("foo")
    end
  end

  describe "local plugin" do
    it "is installed when inside an app" do
      allow(Bundler::SharedHelpers).to receive(:find_gemfile).and_return(bundled_app_gemfile)
      gemfile ""
      bundle "plugin install foo --source #{file_uri_for(gem_repo2)}"

      plugin_should_be_installed("foo")
      expect(local_plugin_gem("foo-1.0")).to be_directory
    end

    context "conflict with global plugin" do
      before do
        update_repo2 do
          build_plugin "fubar" do |s|
            s.write "plugins.rb", <<-RUBY
              class Fubar < Bundler::Plugin::API
                command "shout"

                def exec(command, args)
                  puts "local_one"
                end
              end
            RUBY
          end
        end

        # inside the app
        gemfile "source '#{file_uri_for(gem_repo2)}'\nplugin 'fubar'"
        bundle "install"

        update_repo2 do
          build_plugin "fubar", "1.1" do |s|
            s.write "plugins.rb", <<-RUBY
              class Fubar < Bundler::Plugin::API
                command "shout"

                def exec(command, args)
                  puts "global_one"
                end
              end
            RUBY
          end
        end

        # outside the app
        bundle "plugin install fubar --source #{file_uri_for(gem_repo2)}", dir: tmp
      end

      it "inside the app takes precedence over global plugin" do
        bundle "shout"
        expect(out).to eq("local_one")
      end

      it "outside the app global plugin is used" do
        bundle "shout", dir: tmp
        expect(out).to eq("global_one")
      end
    end
  end
end
