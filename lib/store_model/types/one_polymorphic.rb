# frozen_string_literal: true

require "active_model"

module StoreModel
  module Types
    # Implements ActiveModel::Type::Value type for handling an instance of StoreModel::Model
    class OnePolymorphic < OneBase
      include PolymorphicHelper

      # Initializes type for model class
      #
      # @param model_wrapper [Proc] class to handle
      #
      # @return [StoreModel::Types::OnePolymorphic ]
      def initialize(model_wrapper)
        @model_wrapper = model_wrapper
        super()
      end

      # Returns type
      #
      # @return [Symbol]
      def type
        :polymorphic
      end

      # Casts +value+ from DB or user to StoreModel::Model instance
      #
      # @param value [Object] a value to cast
      #
      # @return StoreModel::Model
      def cast_value(value)
        return nil if value.nil?

        if value.is_a?(String)
          decode_and_initialize(value)
        elsif value.respond_to?(:to_h)
          model_instance(value)
        else
          raise_cast_error(value) unless value.class.ancestors.include?(StoreModel::Model)
          value
        end
      end

      # Casts a value from the ruby type to a type that the database knows how
      # to understand.
      #
      # @param value [Object] value to serialize
      #
      # @return [String] serialized value
      def serialize(value)
        return super unless value.is_a?(::Hash) || implements_model?(value.class)

        if value.is_a?(StoreModel::Model)
          ActiveSupport::JSON.encode(
            value,
            serialize_unknown_attributes: value.serialize_unknown_attributes?,
            serialize_enums_using_as_json: value.serialize_enums_using_as_json?
          )
        else
          ActiveSupport::JSON.encode(value)
        end
      end

      protected

      # Check if block returns an appropriate class and raise cast error if not
      #
      # @param value [Object] raw data
      #
      # @return [Class] which implements StoreModel::Model
      def extract_model_klass(value)
        model_klass = @model_wrapper.call(value)

        raise_extract_wrapper_error(model_klass) unless implements_model?(model_klass)

        model_klass
      end

      def raise_cast_error(value)
        raise StoreModel::Types::CastError,
              "failed casting #{value.inspect}, only String, " \
              "Hash or instances which implement StoreModel::Model are allowed"
      end

      def model_instance(value)
        model_klass = extract_model_klass(value)
        value_hash = value.to_h.symbolize_keys
        value_hash = value_hash[:attributes] if value_hash.key?(:attributes)

        known_attrs = model_klass.attribute_names.map(&:to_sym)
        known_values = value_hash.slice(*known_attrs)
        unknown_values = value_hash.except(*known_attrs)

        model_klass.new(known_values).tap do |instance|
          unknown_values.each do |key, val|
            instance.unknown_attributes[key.to_s] = val
          end
        end
      end
    end
  end
end
