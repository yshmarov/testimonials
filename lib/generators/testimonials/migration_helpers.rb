# frozen_string_literal: true

module Testimonials
  module Generators
    # Shared bits every migration-writing generator needs.
    module MigrationHelpers
      private

      def migration_version
        "[#{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}]"
      end

      # Follow the host's own key type instead of forcing bigint. An app that
      # keys its models with uuids sets this, and its
      # `active_storage_attachments.record_id` is then a uuid column — bigint
      # tables here could never take a video or avatar attachment, because a
      # uuid foreign key has nowhere to point.
      #
      # Same lookup Rails' own Active Storage, Action Text and Action Mailbox
      # migrations do, so a host that set it once gets consistent tables from
      # all of them.
      #
      # Rendered as a `create_table` option rather than a bare value, because a
      # template is expanded at generate time: emitting the method name would
      # put `id: primary_key_type` in the migration, where nothing defines it.
      # A host with no setting gets no option at all, so the migration reads
      # exactly as it always did.
      def primary_key_type_option
        config = Rails.configuration.generators
        type = config.options[config.orm][:primary_key_type]
        type ? ", id: :#{type}" : ''
      end
    end
  end
end
