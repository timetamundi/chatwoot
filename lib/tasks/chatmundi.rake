namespace :chatmundi do
  desc 'Ensure the technical ChatMundi user has access to every account and inbox'
  task ensure_technical_user_access: :environment do
    user = Chatmundi::EnsureTechnicalUserAccessService.call

    puts "Technical user access ensured for #{user.email} (user_id=#{user.id})."
    puts "Accounts: #{user.account_users.count}; inboxes: #{user.inbox_members.count}."
  end
end
