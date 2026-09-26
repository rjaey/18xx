# frozen_string_literal: true

require_relative '../../../step/base'
require_relative '../../../step/auctioner'

module Engine
  module Game
    module G18Africa
      module Step
        # Discarded cards are nominated in turn and auctioned clockwise; any increment,
        # starting bids may be zero, passing players are out [1.3].
        # The winner takes the card into hand, i.e. the right to buy it later at printed cost.
        class InitialAuction < Engine::Step::Base
          include Engine::Step::Auctioner

          ACTIONS = %w[bid pass].freeze

          def setup
            setup_auction
            @auctioning = nil
            @active_bidders = []
            @nominator = @game.players.first
          end

          def name
            'Initial Auction'
          end

          def description
            @auctioning ? "Bid on #{@auctioning.name}" : 'Nominate a card and place an opening bid'
          end

          attr_reader :auctioning

          def available
            @auctioning ? [@auctioning] : @game.auction_cards
          end

          # One row per company in alphabetical order of the abbreviations (Director's Certificate
          # first), Privates in a last row; the shuffled auction order itself is left untouched.
          # During an auction the card up for bids comes first and the others stay visible for
          # overview; the view only offers bids on the card being auctioned.
          def tiered_auction_companies
            others = @game.auction_cards - [@auctioning]
            cards = others.sort_by { |card| @game.card_sort_key(card) }
            rows = cards.chunk_while { |a, b| @game.card_group(a) == @game.card_group(b) }.to_a
            @auctioning ? [[@auctioning]] + rows : rows
          end

          def active_entities
            return [] if finished?

            @auctioning ? [@active_bidders.first] : [@nominator]
          end

          def actions(entity)
            return [] if finished? || entity != current_entity

            @auctioning ? ACTIONS : %w[bid]
          end

          def finished?
            @game.auction_cards.empty?
          end

          def may_bid?(company)
            @auctioning.nil? || company == @auctioning
          end

          def may_purchase?(_company)
            false
          end

          def min_bid(company)
            return 0 if @bids[company].empty?

            highest_bid(company).price + min_increment
          end

          def min_increment
            1
          end

          def max_bid(player, _company)
            player.cash
          end

          def pass_description
            'Pass'
          end

          def committed_cash(_player, _show_hidden = false)
            0
          end

          def process_bid(action)
            player = action.entity
            card = action.company

            unless @auctioning
              raise GameError, "#{card.name} is not up for auction" unless @game.auction_cards.include?(card)

              @auctioning = card
              @active_bidders = @game.players.rotate(@game.players.index(player))
              @log << "#{player.name} nominates #{card.name}"
            end

            add_bid(action)
            @log << "#{player.name} bids #{@game.format_currency(action.price)} for #{card.name}"
            @active_bidders.rotate!
            resolve_auction if @active_bidders.one?
          end

          def process_pass(action)
            player = action.entity
            @log << "#{player.name} passes on #{@auctioning.name}"
            @active_bidders.delete(player)
            resolve_auction if @active_bidders.one?
          end

          protected

          def active_auction
            yield @auctioning, @bids[@auctioning] if @auctioning
          end

          def resolve_auction
            bid = highest_bid(@auctioning)
            player = bid.entity
            card = @auctioning

            player.spend(bid.price, @game.bank) if bid.price.positive?
            @game.remove_card(card)
            player.hand << card
            @game.sort_hand!(player)
            @log << "#{player.name} wins #{card.name} for #{@game.format_currency(bid.price)} and takes it into hand"

            @bids.clear
            @auctioning = nil
            @active_bidders = []
            @nominator = @game.players[(@game.players.index(@nominator) + 1) % @game.players.size]
          end
        end
      end
    end
  end
end
