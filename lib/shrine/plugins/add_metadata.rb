# frozen_string_literal: true

class Shrine
  module Plugins
    # The `add_metadata` plugin provides a convenient method for extracting and
    # adding custom metadata values.
    #
    #     plugin :add_metadata
    #
    #     add_metadata :exif do |io, context|
    #       begin
    #         Exif::Data.new(io).to_h
    #       rescue Exif::NotReadable # not a valid image
    #         {}
    #       end
    #     end
    #
    # The above will add "exif" to the metadata hash, and also create the
    # `#exif` reader method on Shrine::UploadedFile.
    #
    #     image.metadata["exif"]
    #     # or
    #     image.exif
    #
    # You can also extract multiple metadata values at once, by using
    # `add_metadata` without an argument and returning a hash of metadata.
    #
    #     add_metadata do |io, context|
    #       begin
    #         data = Exif::Data.new(io)
    #       rescue Exif::NotReadable # not a valid image
    #         next {}
    #       end
    #
    #       { date_time:     data.date_time,
    #         flash:         data.flash,
    #         focal_length:  data.focal_length,
    #         exposure_time: data.exposure_time }
    #     end
    #
    # In this case Shrine won't automatically create reader methods for the
    # extracted metadata on Shrine::UploadedFile, but you can create them via
    # `#metadata_method`.
    #
    #     metadata_method :date_time, :flash
    #
    # The `io` might not always be a file object, so if you're using an
    # analyzer which requires the source file to be on disk, you can use
    # `Shrine.with_file` to ensure you have a file object.
    #
    #     add_metadata do |io, context|
    #       movie = Shrine.with_file(io) { |file| FFMPEG::Movie.new(file.path) }
    #
    #       { "duration"   => movie.duration,
    #         "bitrate"    => movie.bitrate,
    #         "resolution" => movie.resolution,
    #         "frame_rate" => movie.frame_rate }
    #     end
    #
    # Any previously extracted metadata can be accessed via
    # `context[:metadata]`:
    #
    #     add_metadata :foo do |io, context|
    #       context[:metadata] #=>
    #       # {
    #       #   "size"      => 239823,
    #       #   "filename"  => "nature.jpg",
    #       #   "mime_type" => "image/jpeg"
    #       # }
    #
    #       "foo"
    #     end
    #
    #     add_metadata :bar do |io, context|
    #       context[:metadata] #=>
    #       # {
    #       #   "size"      => 239823,
    #       #   "filename"  => "nature.jpg",
    #       #   "mime_type" => "image/jpeg",
    #       #   "foo"       => "foo"
    #       # }
    #
    #       "bar"
    #     end
    module AddMetadata
      def self.configure(uploader)
        uploader.opts[:metadata] = []
      end

      module ClassMethods
        def add_metadata(name = nil, **options, &block)
          opts[:metadata] << [name, options, block]

          metadata_method(name) if name
        end

        def metadata_method(*names)
          names.each { |name| _metadata_method(name) }
        end

        private

        def _metadata_method(name)
          self::UploadedFile.send(:define_method, name) do
            metadata[name.to_s]
          end
        end
      end

      module InstanceMethods
        def extract_metadata(io, context = {})
          metadata = super
          context  = context.merge(metadata: metadata)

          extract_custom_metadata(io, context)

          metadata
        end

        private

        def extract_custom_metadata(io, context)
          opts[:metadata].each do |name, options, block|
            result   = instance_exec(io, context, &block)
            metadata = {}

            if name
              metadata[name.to_s] = result
            else
              metadata.merge!(result) if result
            end

            # convert symbol keys to strings
            metadata.keys.each do |key|
              metadata[key.to_s] = metadata.delete(key) if key.is_a?(Symbol)
            end

            context[:metadata].merge!(metadata)

            # rewind between metadata blocks
            io.rewind
          end
        end
      end
    end

    register_plugin(:add_metadata, AddMetadata)
  end
end
