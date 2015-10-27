# name: Group Sync
# about: Syncs Filmsoc and Discourse groups
# version: 0.1
# authors: Thomas Purchas
# url: https://github.com/WarwickFilmSoc/discourse-group-sync
enabled_site_setting :group_sync_enabled

module ::GroupSync
  def self.sync_users(users)
    group_mapping = {
      "exec" => ["status_code[1003]"],
      "it_team" => ["status_code[4002]"],
      "q_proj" => ["status_code[3010]", "status_code[3009]", "status_code[3011]"],
      "t_proj" => ["status_code[3006]"],
      "duty_managers" => ["status_code[3005]"],
      "t_dm" => ["status_code[3003]"],
      "editors" => ["status_code[4004]"],
      "tech_team" => ["status_code[4001]"]
    }

    crew = ["status_code[3002]", "status_code[3001]", 
            "status_code[1004]", "status_code[1002]"]
    group_mapping.each do |group, field|
      crew.append(field)
    end
    group_mapping["crew"] = crew

    users.each do |user|
      group_mapping.each do |group_name, custom_fields|
        group = Group.find_by_name(group_name)

        unless group.nil?
          group_inclusion = false

          custom_fields.each do |custom_field|
            if user.custom_fields[custom_field] == "true"
              group_inclusion = true
              break
            end
          end

          if group_inclusion && !user.groups.include?(group)
            group.add(user)
          elsif !group_inclusion && user.groups.include?(group)
            group.remove(user)
          end
        end
      end
    end

    # Fire a trigger for other plugins to listen too
    DiscourseEvent.trigger(:users_groups_synced, users)
  end
end

after_initialize do
  user_sync = Proc.new do |badge_id, user_id|
    if SiteSetting.group_sync_enabled
      Sidekiq::Client.enqueue_in(1.minutes, GroupSync::GroupSyncJob, user_ids: [user_id])
      DiscourseEvent.trigger(:groups_synced)
    end
  end

  DiscourseEvent.on(:user_badge_granted, &user_sync)
  DiscourseEvent.on(:user_badge_removed, &user_sync)


  module ::GroupSync
    class GroupSyncJob < ::Jobs::Scheduled
      every 1.day

      def execute(args)
        if SiteSetting.group_sync_enabled
          user_ids = args[:user_ids]
          if user_ids
            users = user_ids.map {|n| User.find_by(id: n)}
            GroupSync.sync_users(users)
          else
            GroupSync.sync_users(User.all)
          end
          DiscourseEvent.trigger(:groups_synced)
        end
      end
    end
  end
end
