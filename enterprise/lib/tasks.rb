# Load all rake tasks from the enterprise/lib/tasks directory
require "rake"
extend Rake::DSL

module Tasks
  Dir.glob(File.join(File.dirname(__FILE__), 'tasks', '*.rake')).each { |r| load r }
end
