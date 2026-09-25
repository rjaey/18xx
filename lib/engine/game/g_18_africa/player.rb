# frozen_string_literal: true

require_relative '../../player'

module Engine
  module Game
    module G18Africa
      class Player < Engine::Player
        # Cards held in hand are options to buy, they are not owned [1.3]
        attr_accessor :hand

        def initialize(id, name)
          @hand = []
          super
        end
      end
    end
  end
end
