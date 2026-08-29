# frozen_string_literal: true

require "base64"

# Encodes and decodes model primary keys into URL-safe signed tokens.
#
# HOW IT WORKS:
# 1. The raw PK is signed with ActiveSupport::MessageVerifier using a
#    model-specific salt — "SecureId/Payment" differs from
#    "SecureId/PortalMerchantApplication". A token for one model cannot
#    decode for another even if the underlying PK values are identical.
# 2. The signed value is Base64 URL-safe encoded to remove characters
#    that break routing.
# 3. Decoding reverses these steps. Invalid signature → nil. Controllers
#    call decode_id which raises RecordNotFound on nil → 404, never 500.
#
# In lib/ not app/models/concerns/: to_param overriding is invisible.
# SecureId is explicit at every call site — views call SecureId.encode(record),
# controllers call decode_id(Model, params[:id]).
module SecureId
  def self.encode(record)
    model_class = record.class
    raw_value   = record.public_send(model_class.primary_key).to_s.strip
    signed      = verifier_for(model_class).generate(raw_value)
    Base64.urlsafe_encode64(signed, padding: false)
  end

  def self.decode(model_class, encoded_id)
    return nil if encoded_id.blank?

    decoded       = Base64.urlsafe_decode64(encoded_id)
    primary_value = verifier_for(model_class).verify(decoded)
    pk_col        = model_class.primary_key

    if string_primary_key?(model_class, pk_col)
      trimmed = Arel::Nodes::NamedFunction.new("TRIM", [ model_class.arel_table[pk_col] ])
      model_class.where(trimmed.eq(primary_value)).first
    else
      model_class.find_by(pk_col => primary_value)
    end
  rescue ArgumentError, ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end

  def self.verifier_for(model_class)
    @verifiers ||= {}
    @verifiers[model_class.name] ||= ActiveSupport::MessageVerifier.new(
      Rails.application.key_generator.generate_key("SecureId/#{model_class.name}"),
      digest: "SHA256"
    )
  end

  def self.string_primary_key?(model_class, pk_col)
    model_class.columns_hash[pk_col]&.type&.in?(%i[string text])
  end

  private_class_method :verifier_for, :string_primary_key?
end
