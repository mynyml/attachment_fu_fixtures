module Mynyml
  module AttachmentFuFixtures
    class AttachmentFileNotFound < ArgumentError # :nodoc:
    end

    # In order to set model ids, fixtures are inserted manually. The following
    # overrides the insertion to trigger some attachment_fu functionality before
    # it gets added to the db
    def insert_fixture_with_attachment(fixture, table_name)
      if klass = attachment_model?(fixture)

        fixture   = fixture.to_hash
        full_path = fixture.delete('attachment_file')
        mime_type = fixture.delete('content_type') || guess_mime_type(full_path) || 'image/png'
        assert_attachment_exists(full_path)

        require 'action_controller/test_process'
        attachment = klass.new
        attachment.uploaded_data = ActionController::TestUploadedFile.new(full_path, mime_type)
        attachment.instance_variable_get(:@attributes)['id'] = fixture['id'] #pwn id
        attachment.valid? #trigger validation for the callbacks
        attachment.send(:after_process_attachment) #manually call after_save callback

        fixture = Fixture.new(attachment.attributes.update(fixture), klass)
      end
      insert_fixture_without_attachment(fixture, table_name)
    end
    
    private
      def attachment_model?(fixture)
        klass = fixture.model_class
        (klass && klass.instance_methods.include?('uploaded_data=')) ? klass : nil
      end

      # if content_type isn't specified, attempt to use file(1)
      # todo: confirm that `file` silently fails when not available
      # todo: test on win32
      def guess_mime_type(path)
        return nil
        #test behaviour on windows before using this
        type = `file #{path} -ib 2> /dev/null`.chomp
        type.blank? ? nil : type
      end

      def assert_attachment_exists(path)
        unless path && File.exist?(path)
          raise AttachmentFileNotFound, "Couldn't find attachment_file #{path}"
        end
      end
  end
end

# Prevents a problem known to happen with SQLite3 when thumbnails are created
# (raises a SQLite3::SQLException "SQL login error or missing database")
Technoweenie::AttachmentFu::InstanceMethods.module_eval do
  def create_or_update_thumbnail_with_damage_control(*args,&block)
    create_or_update_thumbnail_without_damage_control(*args,&block)
  rescue SQLite3::SQLException, Exception
    #puts "Exception Cought: #{$!.inspect}"
  end
  alias_method_chain :create_or_update_thumbnail, :damage_control
end
