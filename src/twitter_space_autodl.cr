require "log"

require "./config"
require "./utils"
require "./twitter"

PERIOD = 10.seconds

CONFIG = Config.from_yaml(File.read("./config.yml"))
Utils.output_folder = CONFIG.output_folder

Log.setup_from_env
Log.info { "Starting..." }

twitter = Twitter.new CONFIG.twitter
processing = [] of String

Signal::USR1.trap do
  Log.info { "USR1 recived, currently processing #{processing.size} spaces (#{processing.join(", ")})" }
end

loop do
  Log.debug { "Retrieve fleetline" }
  fleets = twitter.fleetline["threads"].as_a
  Log.debug { "Got #{fleets.size} fleets" }
  fleets.each do |fleet|
    space_nil = fleet["live_content"]?.try &.["audiospace"]?
    if space_nil
      space = space_nil.not_nil!
      id = space["broadcast_id"].as_s
      username = twitter.get_username space["creator_twitter_user_id"].as_i64.to_s
      title = space["title"]?.try(&.as_s) || "twitter-space"
      date = space["start"].as_s[0...16].gsub(/[-:]/){}.gsub("T"){"-"}
      fn = Utils.filename(username, date, title)
      if !processing.includes?(id) && !File.exists?(fn)
        Log.info { "Downloading #{date} #{title} By #{username}" }
        playlist = twitter.get_playlist id
        processing.push id
        spawn do
          cnt = 0
          until HTTP::Client.get(playlist).success?
            cnt += 1
            raise "HTTP 404" if cnt > 8
            sleep 1.second
          end
          tmpfn = "#{fn}.tmp.aac"
          process = Process.new "ffmpeg", {"-y", "-hide_banner", "-loglevel", "error", "-i", playlist, "-c", "copy", tmpfn}, error: Process::Redirect::Inherit
          status = process.wait
          Log.debug { status }
          if File.exists? tmpfn
            if status.success?
              File.rename tmpfn, fn
              Log.info { "#{date} #{title} By #{username} done." }
            else
              File.rename tmpfn, "#{fn}.failed"
              Log.info { "#{date} #{title} By #{username} failed, keep failed file!" }
            end
          else
            Log.info { "#{date} #{title} By #{username} failed without any file!" }
          end
        rescue ex : Exception
          Log.error { ex }
        ensure
          processing.delete id
        end
      end
    end
  rescue ex : Exception
    Log.error { ex }
  end
  sleep PERIOD
rescue ex : Twitter::RateLimited
  if ex.reset
    time = ex.reset.not_nil! - Time.utc
    Log.info { "RateLimited, wait #{time.total_seconds.to_i}s" }
    sleep time
    Log.info { "Retry" }
  else
    Log.info { "RateLimited, Reset time unknown" }
    sleep PERIOD
  end
end

