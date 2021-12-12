require "yaml"

struct Config
  struct Twitter
    include YAML::Serializable
    property user_token : String
    property user_token_secret : String
    property app_key : String
    property app_secret : String
    property proxy_host : String
    property proxy_port : Int32
  end

  include YAML::Serializable
  property twitter : Twitter
  property output_folder : String
end
