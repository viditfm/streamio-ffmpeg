require 'time'
require 'json'

module FFMPEG
  class Movie
    attr_reader :path, :duration, :time, :bitrate, :rotation, :creation_time, :size
    attr_reader :video_codec, :video_bitrate, :colorspace, :width, :height, :sar, :dar, :frame_rate
    attr_reader :audio_codec, :audio_bitrate, :audio_sample_rate, :audio_channels
    attr_reader :container, :error_code, :error_message

    def initialize(path)
      raise Errno::ENOENT, "the file '#{path}' does not exist" unless File.exists?(path)

      @path = path

      command = "#{FFMPEG.ffprobe_binary} -v quiet -of json -show_format -show_streams -show_error #{Shellwords.escape(path)}"
      output = `#{command}`
      fix_encoding(output)
    
      movie_info = JSON.parse(output)

      if movie_info['error']
        @error_code = movie_info['error']['code']
        @error_message = movie_info['error']['message']
        return
      end

      format_info = movie_info['format']
      @size = format_info['size'].to_i
      @container = format_info['format_name']
      @duration = format_info['duration'].to_f.round(2)
      @time = format_info['start_time'].to_f 

      if format_info['tags'] && format_info['tags']['creation_time']
        @creation_time = Time.parse(format_info['tags']['creation_time'])
      end

      @bitrate = format_info['bit_rate'] ? (format_info['bit_rate'].to_i / 1000) : nil

      video_info = movie_info['streams'].select {|s| s['codec_type'] == 'video' }.first
      audio_info = movie_info['streams'].select {|s| s['codec_type'] == 'audio' }.first

      if video_info
        @video_codec = video_info['codec_name']
        @colorspace = video_info['pix_fmt']
        @video_bitrate = video_info['bit_rate'] ? (video_info['bit_rate'].to_i / 1000) : nil
        @width = video_info['width']
        @height = video_info['height']
        @sar = video_info['sample_aspect_ratio']
        @dar = video_info['display_aspect_ratio']

        if video_info['tags'] && video_info['tags']['rotate']
          @rotation = video_info['tags']['rotate'].to_i
        end

        if (average_frame_rate = video_info['avg_frame_rate'])
          frames, seconds = video_info['avg_frame_rate'].split('/')
          @frame_rate = (frames.to_f / seconds.to_f).round(2)
        end
      end

      if audio_info
        @audio_codec = audio_info['codec_name']
        @audio_channels = audio_info['channels']
        @audio_bitrate = audio_info['bit_rate'] ? (audio_info['bit_rate'].to_i / 1000) : nil
        @audio_sample_rate = audio_info['sample_rate'] ? audio_info['sample_rate'].to_i : nil
      end
    end

    def valid?
      !(@error_code || @error_message) 
    end

    def has_video?
      !!@video_codec
    end

    def has_audio?
      !!@audio_codec
    end

    def duration
      @duration || 0
    end

    def resolution
      (@width && @height) ? [@width, @height].join('x') : nil 
    end

    def calculated_aspect_ratio
      aspect_from_dar || aspect_from_dimensions
    end

    def calculated_pixel_aspect_ratio
      aspect_from_sar || 1
    end

    def transcode(output_file, options = EncodingOptions.new, transcoder_options = {}, &block)
      Transcoder.new(self, output_file, options, transcoder_options).run &block
    end

    def screenshot(output_file, options = EncodingOptions.new, transcoder_options = {}, &block)
      Transcoder.new(self, output_file, options.merge(screenshot: true), transcoder_options).run &block
    end

    protected
    def aspect_from_dar
      return nil unless dar
      w, h = dar.split(":")
      aspect = w.to_f / h.to_f
      aspect.zero? ? nil : aspect
    end

    def aspect_from_sar
      return nil unless sar
      w, h = sar.split(":")
      aspect = w.to_f / h.to_f
      aspect.zero? ? nil : aspect
    end

    def aspect_from_dimensions
      aspect = width.to_f / height.to_f
      aspect.nan? ? nil : aspect
    end

    def fix_encoding(output)
      output[/test/] # Running a regexp on the string throws error if it's not UTF-8
    rescue ArgumentError
      output.force_encoding("ISO-8859-1")
    end
  end
end
