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
            corporation = current_entity
            return [] unless corporation&.corporation?

            assignable = assignable_concessions(corporation)
            return [] if assignable.empty?
            return [] if entity != corporation && !assignable.include?(entity)

            ACTIONS
          end

          # Available throughout the turn, e.g. once the track laid this turn reaches the Commodity
          def blocks?
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

          # Used by the Abilities bar once the Concession is selected
          def assignable_corporations(concession)
            corporation = current_entity
            assignable_concessions(corporation).include?(concession) ? [corporation] : []
          end

          # Either the Company is given the clicked Concession, or the selected Concession is assigned to it
          def process_assign(action)
            corporation, concession = action.entity.corporation? ? [action.entity, action.target] : [action.target, action.entity]
            if corporation != current_entity || !assignable_concessions(corporation).include?(concession)
              raise GameError, "#{corporation.name} cannot be given #{concession.name}"
            end

            @game.assign_concession(corporation, concession)
          end
        end
      end
    end
  end
end
