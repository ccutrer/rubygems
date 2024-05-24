# frozen_string_literal: true

module Bundler
  # Manages which plugins are installed and their sources. This also is supposed to map
  # which plugin does what (currently the features are not implemented so this class is
  # now a stub class).
  module Plugin
    class Index
      class CommandConflict < PluginError
        def initialize(plugin, commands)
          msg = "Command(s) `#{commands.join("`, `")}` declared by #{plugin} are already registered."
          super msg
        end
      end

      class SourceConflict < PluginError
        def initialize(plugin, sources)
          msg = "Source(s) `#{sources.join("`, `")}` declared by #{plugin} are already registered."
          super msg
        end
      end

      attr_reader :commands

      def initialize
        @plugin_paths = {}
        @commands = {}
        @sources = {}
        @hooks = {}
        @load_paths = {}

        begin
          load_index(global_index_file, true)
        rescue GenericSystemCallError
          # no need to fail when on a read-only FS, for example
          nil
        end
        load_index(local_index_file) if SharedHelpers.in_bundle?
      end

      # This function is to be called when a new plugin is installed. This
      # function shall add the functions of the plugin to existing maps and also
      # the name to source location.
      #
      # @param [String] name of the plugin to be registered
      # @param [String] path where the plugin is installed
      # @param [Array<String>] load_paths for the plugin
      # @param [Array<String>] commands that are handled by the plugin
      # @param [Array<String>] sources that are handled by the plugin
      def register_plugin(name, path, load_paths, commands, sources, hooks)
        old_commands = @commands.dup

        common = commands & @commands.keys
        raise CommandConflict.new(name, common) unless common.empty?
        commands.each {|c| @commands[c] = name }

        common = sources & @sources.keys
        raise SourceConflict.new(name, common) unless common.empty?
        sources.each {|k| @sources[k] = name }

        hooks.each do |event|
          event_hooks = (@hooks[event] ||= []) << name
          event_hooks.uniq!
        end

        @plugin_paths[name] = path
        @load_paths[name] = load_paths
        save_index
      rescue StandardError
        @commands = old_commands
        raise
      end

      def unregister_plugin(name)
        @commands.delete_if {|_, v| v == name }
        @sources.delete_if {|_, v| v == name }
        @hooks.each do |hook, names|
          names.delete(name)
          @hooks.delete(hook) if names.empty?
        end
        @plugin_paths.delete(name)
        @load_paths.delete(name)
        save_index
      end

      # Path of default index file
      def index_file
        Plugin.root.join("index")
      end

      # Path where the global index file is stored
      def global_index_file
        Plugin.global_root.join("index")
      end

      # Path where the local index file is stored
      def local_index_file
        Plugin.local_root.join("index")
      end

      def plugin_path(name)
        Pathname.new @plugin_paths[name]
      end

      def load_paths(name)
        @load_paths[name]
      end

      # Fetch the name of plugin handling the command
      def command_plugin(command)
        @commands[command]
      end

      def installed?(name)
        @plugin_paths[name]
      end

      def installed_plugins
        @plugin_paths.keys
      end

      def plugin_commands(plugin)
        @commands.find_all {|_, n| n == plugin }.map(&:first)
      end

      def source_plugin(name)
        @sources[name]
      end

      # Returns the list of plugin names handling the passed event
      def hook_plugins(event)
        @hooks[event] || []
      end

      # This plugin is installed inside the .bundle/plugin directory,
      # and thus is managed solely by Bundler
      def installed_in_plugin_root?(name)
        return false unless (path = installed?(name))

        path.start_with?("#{Plugin.root}/")
      end

      # generate an in-memory lockfile from the index
      def generate_lockfile(sources, dependencies)
        specs = specs(sources, dependencies, :lazy)

        require_relative "../lockfile_generator"
        LockfileGenerator.generate(IndexDefinition.new(sources, specs, dependencies))
      end

      def specs(sources, dependencies, type)
        sources.cached!
        default_source = sources.global_rubygems_source

        installed_plugins.filter_map do |plugin|
          path = plugin_path(plugin)
          # path gems may have a gemspec, which is the most trustworthy
          # way to determine the version
          version = if (gemspec = path.join("#{plugin}.gemspec")).file?
            spec = Gem::Specification.load(gemspec.to_s)
            spec.full_gem_path = path.to_s
            spec.version
          elsif (version_index = path.to_s.index("#{plugin}-"))
            path.to_s[(version_index + plugin.length + 1)..]
          end

          next unless version

          dep = dependencies.find {|d| d.name == plugin }
          next unless dep

          lazy_spec = LazySpecification.new(plugin, version, nil, dep.source || default_source)
          next unless lazy_spec.satisfies?(dep)

          if type == :lazy
            lazy_spec
          else
            spec.source = dep.source || default_source
            spec
          end
        end
      end

      private

      # Reads the index file from the directory and initializes the instance
      # variables.
      #
      # It skips the sources if the second param is true
      # @param [Pathname] index file path
      # @param [Boolean] is the index file global index
      def load_index(index_file, global = false)
        SharedHelpers.filesystem_access(index_file, :read) do |index_f|
          valid_file = index_f&.exist? && !index_f.size.zero?
          break unless valid_file

          data = index_f.read

          require_relative "../yaml_serializer"
          index = YAMLSerializer.load(data)

          @commands.merge!(index["commands"])
          @hooks.merge!(index["hooks"])
          @load_paths.merge!(index["load_paths"])
          @plugin_paths.merge!(index["plugin_paths"])
          @sources.merge!(index["sources"]) unless global
        end
      end

      # Should be called when any of the instance variables change. Stores the
      # instance variables in YAML format. (The instance variables are supposed
      # to be only String key value pairs)
      def save_index
        index = {
          "commands" => @commands,
          "hooks" => @hooks,
          "load_paths" => @load_paths,
          "plugin_paths" => @plugin_paths,
          "sources" => @sources,
        }

        require_relative "../yaml_serializer"
        SharedHelpers.filesystem_access(index_file) do |index_f|
          FileUtils.mkdir_p(index_f.dirname)
          File.open(index_f, "w") {|f| f.puts YAMLSerializer.dump(index) }
        end
      end
    end
  end
end
