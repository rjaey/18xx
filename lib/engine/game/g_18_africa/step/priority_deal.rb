# frozen_string_literal: true

require_relative '../../../step/base'
require_relative '../../../round/choices'

module Engine
  module Game
    module G18Africa
      module Round
        class PriorityDeal < Engine::Round::Choices
          def select_entities
            @game.players
          end

          def name
            'Priority Deal'
          end
        end
      end

      module Step
        # Madianos Olive Groves: at the start of a Stock Round the owning player may take the
        # Priority Deal, once per game [5]
        class PriorityDeal < Engine::Step::Base
          ACTIONS = %w[choose].freeze

          def setup
            @decided = false
          end

          def active_entities
            return [] if @decided

            [@game.company_by_id('P6').owner]
          end

          def actions(entity)
            return [] if @decided || entity != current_entity

            ACTIONS
          end

          def description
            'Madianos Olive Groves'
          end

          def choice_name
            'Take the Priority Deal?'
          end

          def choices
            { 'take' => 'Take the Priority Deal', 'keep' => 'Keep the ability for later' }
          end

          def process_choose(action)
            player = action.entity
            if action.choice == 'take'
              @game.use_private_ability!('P6', player)
              @game.players.rotate!(@game.players.index(player))
              @log << "#{player.name} has the Priority Deal"
            else
              @log << "#{player.name} does not use Madianos Olive Groves"
            end
            @decided = true
          end
        end
      end
    end
  end
end
