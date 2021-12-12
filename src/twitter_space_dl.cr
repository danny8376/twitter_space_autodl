require "log"

require "./config"
require "./utils"
require "./twitter"

CONFIG = Config.from_yaml(File.read("./config.yml"))
Utils.output_folder = CONFIG.output_folder

Dir.cd(Process.executable_path || ".")

Log.setup_from_env
Log.info { "Starting..." }

twitter = Twitter.new CONFIG.twitter

ARGV.each do |id_url|
  match1 = /https?:\/\/twitter\.com\/i\/spaces\/(\w+)\??/.match id_url
  match2 = /^\w+$/
  id = if match1
         match1[1]
       elsif match2
         id_url
       else
         ""
       end
  unless id.empty?
    info = twitter.get_spaceinfo id
    meta_nil = info["data"]["audioSpace"]["metadata"]?
    if meta_nil
      meta = meta_nil.not_nil!
      username = meta["creator_results"]["result"]["legacy"]["screen_name"].as_s
      date = Time.unix_ms(meta["started_at"].as_i64).to_s("%Y%m%d-%H%M")
      title = meta["title"]?.try(&.as_s) || "twitter-space"
      Log.info { "Downloading #{date} #{title} By #{username}" }
      playlist = twitter.get_playlist_mkey meta["media_key"]
      archive = meta["state"].as_s == "Ended"
      fn = Utils.filename(username, date, title, archive)
      tmpfn = "#{fn}.part.aac"
      result = Process.run "ffmpeg", {"-y", "-hide_banner", "-i", playlist, "-c", "copy", archive ? tmpfn : fn}, error: Process::Redirect::Inherit
      if archive
        if result.success? && File.exists?(tmpfn)
          File.rename tmpfn, fn
          Log.info { "#{date} #{title} By #{username} done." }
        else
          Log.info { "#{date} #{title} By #{username} failed!" }
        end
      else
        if result.normal_exit?
          Log.info { "#{date} #{title} By #{username} finished." }
        else
          Log.info { "#{date} #{title} By #{username} terminated." }
        end
      end
    end
  end
rescue ex : Exception
  Log.error { ex }
end
