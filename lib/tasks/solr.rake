require 'fileutils'
include FileUtils

def solr_config
  YAML::load_file(RAILS_ROOT + '/config/solr.yml')[RAILS_ENV]
end

def solr_pid
  "#{RAILS_ROOT}/tmp/pids/solr_#{RAILS_ENV}.pid"
end

def solr_port
  URI.parse(solr_config['url']).port
end

def default_solr_path
  "#{RAILS_ROOT}/vendor/plugins/acts_as_solr/solr"
end

def solr_path
  solr_config['path'] || default_solr_path
end

def solr_index
  "#{solr_path}/index/#{RAILS_ENV}"
end

namespace :solr do
  desc 'Starts Solr. Options accepted: RAILS_ENV=your_env, PORT=XX. Defaults to development if none.'
  task :start => :environment do
    begin
      n = Net::HTTP.new('127.0.0.1', solr_port)
      n.request_head('/').value
    rescue Net::HTTPServerException #responding
      raise "Port #{solr_port} is already in use"
    rescue Errno::ECONNREFUSED #not responding
      Rake::Task["solr:install"].invoke 

      Dir.chdir(solr_path) do
        pid = fork do
          exec "java #{solr_config['jvm_options']} -Dsolr.data.dir=#{solr_index} -Djetty.logs=#{RAILS_ROOT}/log -Djetty.port=#{solr_port} -jar start.jar"
        end
        Process.detach(pid)
        File.open(solr_pid, "w"){ |f| f << pid}
        puts "Solr started successfully in #{RAILS_ENV} mode on port #{solr_port}, pid: #{pid}."
      end
    end
  end
  
  desc 'Stops Solr. Specify the environment by using: RAILS_ENV=your_env. Defaults to development if none.'
  task :stop => :environment do
    fork do
      if File.exists?(solr_pid)
        File.open(solr_pid, "r") do |f| 
          pid = f.readline
          Process.kill('TERM', pid.to_i)
        end
        File.unlink(solr_pid)
        Rake::Task["solr:destroy_index"].invoke if RAILS_ENV == 'test'
        puts "Solr shutdown successfully."
      else
        raise "PID file not found at #{solr_pid}. Either Solr is not running or no PID file was written."
      end
    end
  end
  
  desc 'Remove Solr index'
  task :destroy_index => :environment do
    raise "In production mode.  I'm not going to delete the index, sorry." if RAILS_ENV == "production"
    if File.exists?(solr_index)
      Dir["#{solr_index}/index/*"].each{|f| File.unlink(f)}
      Dir.rmdir("#{solr_index}/index")
      puts "Index files removed under " + RAILS_ENV + " environment"
    end
  end
  
  desc  'Installs default solr binary into desired path'
  task :install => :environment do
    if File.exists?(solr_path)
      puts "Solr already installed at #{solr_path}"
    else
      cp_r default_solr_path, solr_path
    end
  end
  
  # this task is by Henrik Nyh
  # http://henrik.nyh.se/2007/06/rake-task-to-reindex-models-for-acts_as_solr
  desc %{Reindexes data for all acts_as_solr models. Clears index first to get rid of orphaned records and optimizes index afterwards. RAILS_ENV=your_env to set environment. ONLY=book,person,magazine to only reindex those models; EXCEPT=book,magazine to exclude those models. START_SERVER=true to solr:start before and solr:stop after. BATCH=123 to post/commit in batches of that size: default is 300. CLEAR=false to not clear the index first; OPTIMIZE=false to not optimize the index afterwards.}
  task :reindex => :environment do
    includes = env_array_to_constants('ONLY')
    if includes.empty?
      includes = Dir.glob("#{RAILS_ROOT}/app/models/*.rb").map { |path| File.basename(path, ".rb").camelize.constantize }
    end
    excludes = env_array_to_constants('EXCEPT')
    includes -= excludes
    
    optimize            = env_to_bool('OPTIMIZE',     true)
    start_server        = env_to_bool('START_SERVER', false)
    clear_first         = env_to_bool('CLEAR',       true)
    batch_size          = ENV['BATCH'].to_i.nonzero? || 300
    debug_output        = env_to_bool("DEBUG", false)

    RAILS_DEFAULT_LOGGER.level = ActiveSupport::BufferedLogger::INFO unless debug_output

    if start_server
      puts "Starting Solr server..."
      Rake::Task["solr:start"].invoke 
    end
    
    # Disable solr_optimize
    module ActsAsSolr::CommonMethods
      def blank() end
      alias_method :deferred_solr_optimize, :solr_optimize
      alias_method :solr_optimize, :blank
    end
    
    models = includes.select { |m| m.respond_to?(:rebuild_solr_index) }    
    models.each do |model|
      puts "Rebuilding index for #{model}..."
      model.rebuild_solr_index(batch_size)
    end 

    if models.empty?
      puts "There were no models to reindex."
    elsif optimize
      puts "Optimizing..."
      models.last.deferred_solr_optimize
    end

    if start_server
      puts "Shutting down Solr server..."
      Rake::Task["solr:stop"].invoke 
    end
    
  end
  
  def env_array_to_constants(env)
    env = ENV[env] || ''
    env.split(/\s*,\s*/).map { |m| m.singularize.camelize.constantize }.uniq
  end
  
  def env_to_bool(env, default)
    env = ENV[env] || ''
    case env
      when /^true$/i then true
      when /^false$/i then false
      else default
    end
  end

end

