# frozen_string_literal: true

require_relative '../../../step/token'

module Engine
  module Game
    module G18Africa
      module Step
        # One token per turn at the charter price [3.3.2]. George Edmunds Colonial Factors makes one
        # token lay free, and then the £100 token may be used while a £40 one is left [5]
        class Token < Engine::Step::Token
          def round_state
            super.merge(free_token: false)
          end

          def setup
            super
            @round.free_token = false
          end

          def actions(entity)
            actions = super
            return actions if actions.empty? || !free_token_available?(entity)

            actions + ['choose']
          end

          def free_token_available?(entity)
            !@round.free_token && @game.private_usable?(entity, 'P5')
          end

          def choice_available?(entity)
            free_token_available?(entity)
          end

          def choice_name
            'George Edmunds Colonial Factors'
          end

          def choices
            { 'free_token' => 'Place the next token for free' }
          end

          def process_choose(_action)
            @round.free_token = true
          end

          def available_tokens(entity)
            tokens = super
            return tokens unless @round.free_token

            unused = entity.tokens.reject(&:used)
            unused.empty? ? tokens : [unused.max_by(&:price)]
          end

          def process_place_token(action)
            return super unless @round.free_token

            entity = action.entity
            token = action.token
            price = token.price
            token.price = 0
            super
            token.price = price
            @round.free_token = false
            @game.use_private_ability!('P5', entity)
          end
        end
      end
    end
  end
end
