# frozen_string_literal: true

module ReviewEngine
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true
  end
end
