# frozen_string_literal: true

require_relative '../../../step/base'
require_relative '../../../step/auctioner'
require_relative '../../../round/auction'

module Engine
  module Game
    module G18Africa
      module Round
        class ConcessionAuction < Engine::Round::Auction
          def name
            'Concession Auction'
          end
        end
      end

      module Step
        # After the first set of Operating Rounds the right to choose a Concession is auctioned
        # repeatedly: the Priority Deal holder opens (any amount, including zero), bidding goes
        # clockwise, passing players are out. The winner chooses a Concession; the next auction
        # starts left of the winner. The last Concession is removed from the game [1.5]
        class ConcessionAuction < Engine::Step::Base
          include Engine::Step::Auctioner

          ACTIONS = %w[bid pass].freeze

          attr_reader :auctioning

          def setup
            setup_auction
            @auctioning = nil
            @active_bidders = []
            @winner = nil
            @starter = @game.players.first
          end

          def name
            'Concession Auction'
          end

          def description
            return 'Choose a Concession' if @winner

            @auctioning ? 'Bid for the choice of a Concession' : 'Open the auction for the choice of a Concession'
          end

          # The right to choose is auctioned; the remaining Concessions are shown for information
          def available
            [@game.concession_right] + @game.concessions_available
          end

          def active_entities
            return [] if finished?
            return [@winner] if @winner

            @auctioning ? [@active_bidders.first] : [@starter]
          end

          def actions(entity)
            return [] if finished? || entity != current_entity
            return %w[choose] if @winner

            @auctioning ? ACTIONS : %w[bid]
          end

          def finished?
            @winner.nil? && @game.concessions_available.size <= 1
          end

          def may_bid?(company)
            company == @game.concession_right
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

          def committed_cash(_player, _show_hidden = false)
            0
          end

          def process_bid(action)
            player = action.entity
            unless @auctioning
              @auctioning = @game.concession_right
              @active_bidders = @game.players.rotate(@game.players.index(player))
            end

            add_bid(action)
            @log << "#{player.name} bids #{@game.format_currency(action.price)} for the choice of a Concession"
            @active_bidders.rotate!
            resolve_auction if @active_bidders.one?
          end

          def process_pass(action)
            @log << "#{action.entity.name} passes"
            @active_bidders.delete(action.entity)
            resolve_auction if @active_bidders.one?
          end

          def choice_name
            'Choose a Concession'
          end

          def choices
            @game.concessions_available.to_h { |c| [c.id, "#{c.name}: #{c.desc}"] }
          end

          def process_choose(action)
            player = action.entity
            concession = @game.concessions_available.find { |c| c.id == action.choice }
            raise GameError, 'Unknown Concession' unless concession

            @game.award_concession(player, concession)
            @winner = nil
            @starter = @game.players[(@game.players.index(player) + 1) % @game.players.size]
            @game.remove_last_concession if finished?
          end

          protected

          def active_auction
            yield @auctioning, @bids[@auctioning] if @auctioning
          end

          def resolve_auction
            bid = highest_bid(@auctioning)
            @winner = bid.entity
            @winner.spend(bid.price, @game.bank) if bid.price.positive?
            @log << "#{@winner.name} wins the choice of a Concession for #{@game.format_currency(bid.price)}"
            @bids.clear
            @auctioning = nil
            @active_bidders = []
          end
        end
      end
    end
  end
end
