# frozen_string_literal: true

class PasskeyCredential < ApplicationRecord
  belongs_to :user
end
