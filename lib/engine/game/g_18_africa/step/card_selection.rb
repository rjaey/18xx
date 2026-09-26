# frozen_string_literal: true

require_relative '../../../step/base'

module Engine
  module Game
    module G18Africa
      module Step
        # Each player keeps half of the dealt cards; the discards are auctioned [1.3]
        class CardSelection < Engine::Step::Base
          ACTIONS = %w[select_multiple_companies].freeze

          def actions(entity)
            return [] if finished? || entity != current_entity

            ACTIONS
          end

          def setup
            @choices = Hash.new { |h, k| h[k] = [] }
            @confirmed = 0
          end

          def name
            'Certificate Selection'
          end

          def description
            "Select #{cards_to_keep} cards to keep"
          end

          def pass_description
            'Confirm Selection'
          end

          def cards_to_keep
            @game.class::CERTS_DEALT[@game.players.size] / 2
          end

          def available
            current_entity.hand.sort_by { |c| [c.type, -c.value, c.name] }
          end

          def select_company(player, company)
            if company_selected?(company)
              @choices[player].delete(company)
            else
              @choices[player] << company
            end
          end

          def company_selected?(company)
            @choices[current_entity].include?(company)
          end

          def selected_companies
            @choices[current_entity]
          end

          def selections_completed?
            selected_companies.size == cards_to_keep
          end

          def selection_note
            [
              'Click on a card to select or unselect it. Discarded cards are auctioned off afterwards.',
              "Selected #{selected_companies.size} of #{cards_to_keep} cards.",
            ]
          end

          def process_select_multiple_companies(action)
            player = action.entity
            keep = action.companies
            raise GameError, 'Selected cards are not in hand' unless (keep - player.hand).empty?
            raise GameError, "Must keep exactly #{cards_to_keep} cards" unless keep.size == cards_to_keep

            @game.auction_cards.concat(player.hand - keep)
            player.hand = keep
            @log << "#{player.name} keeps #{keep.size} cards"
            @confirmed += 1
            @round.next_entity_index!
            reveal_discards if finished?
          end

          # Discards are shuffled so nobody knows who discarded what [1.3]
          def reveal_discards
            @game.auction_cards.sort_by! { @game.rand }
            @game.two_player_auction_swap
            @log << "Cards to be auctioned: #{@game.auction_cards.map(&:name).join(', ')}"
          end

          def finished?
            @confirmed == @game.players.size
          end

          def may_purchase?(_company)
            false
          end

          def may_choose?(_company)
            false
          end

          def auctioning; end

          def bids
            {}
          end

          def visible?
            false
          end

          def players_visible?
            false
          end

          def show_companies
            true
          end

          def show_map
            true
          end

          def committed_cash(_player, _show_hidden = false)
            0
          end
        end
      end
    end
  end
end
