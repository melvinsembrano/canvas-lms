require 'fileutils'
require 'lib/i18n_extraction/handlebars_extractor'

# Precompiles handlebars templates into JavaScript function strings
class Handlebars

  class << self

    # Recursively compiles a source directory of .handlebars templates into a
    # destination directory. Immitates the node.js bin script at
    # https://github.com/wycats/handlebars.js/blob/master/bin/handlebars
    #
    # Arguments:
    #   root_path (string) - The root directory to find templates to compile
    #   compiled_path (string) - The destination directory in which to save the
    #     compiled templates.
    #   plugin (string) - Optional plugin to which the files belong. Will be
    #     used in scoping the generated module names. If absent, but a file is
    #     visibly under a plugin, the plugin for that file will be inferred.
    def compile(root_path, compiled_path, plugin=nil)
      files = Dir["#{root_path}/**/**.handlebars"]
      files.each { |file| compile_file file, root_path, compiled_path, plugin }
    end

    # Compiles a single file into a destination directory.
    #
    # Arguments:
    #   file (string) - The file to compile.
    #   root_path - See `compile`
    #   compiled_path - See `compile`
    #   plugin - See `compile`
    def compile_file(file, root_path, compiled_path, plugin=nil)
      require 'execjs'
      id       = file.gsub(root_path + '/', '').gsub(/.handlebars$/, '')
      path     = "#{compiled_path}/#{id}.js"
      dir      = File.dirname(path)
      source   = File.read(file)
      plugin ||= compiled_path =~ /vendor\/plugins\/([^\/]*)\// ? $1 : nil
      js       = compile_template(source, id, plugin)
      FileUtils.mkdir_p(dir) unless File.exists?(dir)
      File.open(path, 'w') { |file| file.write(js) }
    end

    def compile_template(source, id, plugin=nil)
      require 'execjs'
      # if the first letter of the template name is "_", register it as a partial
      # ex: _foobar.handlebars or subfolder/_something.handlebars
      filename = File.basename(id)
      if filename.match(/^_/)
        partial_name = filename.sub(/^_/, "")
        partial_path = id.sub(filename, partial_name)
        partial_registration = "\nHandlebars.registerPartial('#{partial_path}', templates['#{id}']);\n"
      end
      prepared = prepare_i18n(source, id)
      template = context.call "Handlebars.precompile", prepared[:content]
      dependencies = ['compiled/handlebars_helpers']
      dependencies << "i18n!#{normalize(id)}" if prepared[:keys].size > 0

      <<-JS
define('#{plugin ? plugin + "/" : ""}jst/#{id}', #{dependencies.to_json}, function (Handlebars) {
  var template = Handlebars.template, templates = Handlebars.templates = Handlebars.templates || {};
  templates['#{id}'] = template(#{template});
  #{partial_registration}
  return templates['#{id}'];
});
JS
    end

    def normalize(id)
      # String#underscore may not be available
      id.sub(/^_/, '').gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').gsub(/([a-z\d])([A-Z])/,'\1_\2').tr("-", "_").downcase.gsub(/\/_?/, '.')
    end

    def prepare_i18n(source, scope)
      @extractor ||= I18nExtraction::HandlebarsExtractor.new
      scope = scope.sub(/\A_/, '').gsub(/\/_?/, '.')
      keys = []
      content = @extractor.scan(source, :method => :gsub) do |data|
        wrappers = data[:wrappers].map{ |value, delimiter| " w#{delimiter.size-1}=#{value.inspect}" }.join
        keys << data[:key]
        "{{{t #{data[:key].inspect} #{data[:value].inspect} scope=#{scope.inspect}#{wrappers}#{data[:options]}}}}"
      end
      {:content => content, :keys => keys}
    end

    protected

    # Returns the JavaScript context
    def context
      @context ||= self.set_context
    end

    # Compiles and caches the handlebars JavaScript
    def set_context
      handlebars_source = File.read(File.dirname(__FILE__) + '/vendor/handlebars.js')
      @context = ExecJS.compile handlebars_source
    end
  end
end

