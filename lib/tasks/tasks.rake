namespace :tasks do
  desc "Fix due dates for tasks not set to midnight"
  task :fix => :environment do
    tasks = Task.pending
    tasks.each do |task|
      if !task.due_at.nil? and task.due_at.strftime("%H") != "00"
        puts  "updating #{id} from #{task.due_at}"
        puts task.update_attribute(:due_at, task.due_at.midnight.tomorrow)
      end
    end
  end
end
