# frozen_string_literal: true

require_relative '../../../step/base'

module Engine
  module Game
    module G18Africa
      module Step
        # During its turn a Company may be given a Concession by the player controlling it,
        # provided it can run the Concession route [3.4.5]. Click the Concession to assign it.
        class AssignConcession < Engine::Step::Base
          ACTIONS = %w[assign].freeze

          def actions(entity)
            return [] if entity != current_entity || !entity.corporation?
            return [] if assignable_concessions(entity).empty?

            ACTIONS
          end

          def blocking?
            false
          end

          def description
            'Assign a Concession'
          end

          def assignable_concessions(corporation)
            player = corporation.player
            return [] unless player

            player.companies.select { |c| c.type == :concession && @game.can_run_concession?(corporation, c) }
          end

          def process_assign(action)
            corporation = action.entity
            concession = action.target
            unless assignable_concessions(corporation).include?(concession)
              raise GameError, "#{corporation.name} cannot be given #{concession.name}"
            end

            @game.assign_concession(corporation, concession)
          end
        end
      end
    end
  end
end
