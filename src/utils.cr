class Utils
  class_property output_folder = "."

  def self.sanitize_filename(s)
    s.gsub(/(?:[\/<>:"\|\\?\*]|[\s.]$)/) { "#" }
  end

  def self.filename(username, date, title, archive = false)
    path = "#{@@output_folder}/#{sanitize_filename username}"
    Dir.mkdir_p path
    "#{path}/#{date}-#{sanitize_filename title}#{"-part2" unless archive}.aac"
  end
end
