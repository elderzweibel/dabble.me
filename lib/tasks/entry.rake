namespace :entry do

  # rake entry:send_entries_test
  task :send_entries_test => :environment do
    user = User.where(:email=>"admin@dabble.ex").first
    EntryMailer.send_entry(user).deliver_now
  end

  # heroku run bundle exec rake "entry:stats[2017]" --app dabble-me
  task :stats, [:year] => :environment do |_, year:|
    # Stats for 2015
    # 3,872 users created
    # 87,572 entries created
    # 5,017,056 total words
    # 150.4 avg words
    # 28,602,926 characters
    # 857.30 avg characters per post (6.1 tweets)
    # 171,919 were the word "I"

    # Stats for 2016
    # Users created: 1,068
    # Entries created in 2016: 31,832
    # Entries for 2016: 26,032
    # Total words: 4,331,103
    # Avg words per post: 166.37611401352183
    # Total characters: 23,932,366
    # Avg characters per post: 919 (7 tweets)
    # Most Frequent Words: [[\"i\", 163045], [\"and\", 151757], [\"to\", 132691], [\"the\", 130053], [\"a\", 85094], [\"was\", 60419], [\"it\", 54396], [\"of\", 50351], [\"in\", 48510], [\"for\", 42713]]

    # Stats for 2017
    # Users created: 513
    # Entries created in 2017: 26,392
    # Entries for 2017: 23,114
    # Total words: 4,045,874.0
    # Avg words per post: 175.03997577225923
    # Total characters: 22,437,002
    # Avg characters per post: 970 (3.5 280-char tweets)
    # Most Frequent Words: [[\"i\", 151631], [\"and\", 140573], [\"to\", 125157], [\"the\", 124716], [\"a\", 80018], [\"was\", 56392], [\"it\", 50724], [\"of\", 49439], [\"in\", 46545], [\"for\", 42304]]

    p "*"*100
    p "STATS FOR #{year}"
    p "*"*100

    extend ActionView::Helpers::NumberHelper    
    all_entries = Entry.where("date >= '#{year}-01-01'::DATE AND date <= '#{year}-12-31'::DATE") 
    entries_bodies = all_entries.map { |e| ActionView::Base.full_sanitizer.sanitize(e.body) }.join(" ")
    words_counter = WordsCounted.count(entries_bodies)
    total_words = words_counter.token_count.to_f
    avg_words = total_words / all_entries.count
    total_chars = entries_bodies.length
    avg_chars = total_chars / all_entries.count
    avg_tweets_per_post = ((avg_chars).to_f / 280).ceil
    most_frequent = words_counter.token_frequency.first(10)
    p "Users created: #{number_with_delimiter(User.where("created_at >= '#{year}-01-01'::DATE AND created_at <= '#{year}-12-31'::DATE").count)}"
    p "Entries created in #{year}: #{number_with_delimiter(Entry.where("created_at >= '#{year}-01-01'::DATE AND created_at <= '#{year}-12-31'::DATE").count)}"
    p "Entries for #{year}: #{number_with_delimiter(all_entries.count)}"    
    p "Total words: #{number_with_delimiter(total_words)}"
    p "Avg words per post: #{number_with_delimiter(avg_words)}"
    p "Total characters: #{number_with_delimiter(total_chars)}"
    p "Avg characters per post: #{number_with_delimiter(avg_chars)} (#{avg_tweets_per_post} tweets)"
    p "Most Frequent Words: #{most_frequent}"
    p "*"*100
  end

  # heroku run bundle exec rake "entry:stats_by_user[2017]" --app dabble-me
  task :stats_by_user, [:year] => :environment do |_, year:|
    data = []
    User.all.each do |user|
      user_entries = Entry.where("date >= '#{year}-01-01'::DATE AND date <= '#{year}-12-31'::DATE AND user_id = ?", user.id) 
      if user_entries.count > 0
        entries_bodies = user_entries.map { |e| ActionView::Base.full_sanitizer.sanitize(e.body) }.join(" ")
        words_counter = WordsCounted.count(entries_bodies)
        total_words = words_counter.token_count.to_f
        avg_words = total_words / user_entries.count
        total_chars = entries_bodies.length
        avg_chars = total_chars / user_entries.count
        avg_tweets_per_post = ((avg_chars).to_f / 280).ceil
        data << "#{user.email}, #{user_entries.count}, #{avg_words.round(1)}, #{avg_tweets_per_post}"
      end
    end
    p "*"*100
    p "DATA BY USER"
    p "*"*100
    p data
    p "*"*100
  end

  task :send_hourly_entries => :environment do
    users = User.subscribed_to_emails.not_just_signed_up
    users.each do |user|
      # Check if it's the hour they want where they live AND the day where they live that they want it sent: send it.
      if Time.now.in_time_zone(user.send_timezone).hour == user.send_time.hour && user.frequency.include?(Time.now.in_time_zone(user.send_timezone).strftime('%a'))
        # don't keep emailing if we've already sent 3 emails (welcome + 2 weeklys) and the user is not using the service (should decrease spam reports)
        if user.emails_sent > 4 && user.entries.count == 0 && ENV['FREE_WEEK'] != 'true'
          user.update_columns(frequency: nil)
        else
          # Every other week for free users
          if user.is_pro? || (user.is_free? && Time.now.strftime("%U").to_i % 2 == 0) || ENV['FREE_WEEK'] == 'true'
            begin
              EntryMailer.send_entry(user).deliver_now
            rescue StandardError => e
              Rails.logger.warn("Error sending daily entry email to #{user.email}: #{e}")
            end
          end
        end
      end
    end
  end

end
