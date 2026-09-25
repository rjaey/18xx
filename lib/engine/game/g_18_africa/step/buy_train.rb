# frozen_string_literal: true

require_relative '../../../step/buy_train'

module Engine
  module Game
    module G18Africa
      module Step
        # At most one train from the Bank per OR, any number from other Companies,
        # and any number sold back to the Bank, in any order [3.6]
        class BuyTrain < Engine::Step::BuyTrain
          def actions(entity)
            return [] if entity != current_entity

            actions = []
            actions << 'buy_train' if can_buy_train?(entity)
            actions << 'sell_train' if can_sell_train?(entity)
            actions << 'pass' unless actions.empty?
            actions
          end

          def description
            'Buy and Sell Trains'
          end

          def round_state
            super.merge(bought_from_bank: false)
          end

          def setup
            super
            @round.bought_from_bank = false
          end

          def buyable_trains(entity)
            trains = super
            trains = trains.reject { |t| t.owner == @depot } if @round.bought_from_bank
            trains
          end

          def can_buy_train?(entity = nil, _shell = nil)
            entity ||= current_entity
            room?(entity) && buyable_trains(entity).any? do |train|
              entity.cash >= (train.owner == @depot ? train.price : 1)
            end
          end

          def process_buy_train(action)
            from_bank = action.train.owner == @depot
            super
            @round.bought_from_bank = true if from_bank
          end

          def pass_if_cannot_buy_train?(_entity)
            false
          end

          def can_sell_train?(entity)
            entity.corporation? && !entity.trains.empty?
          end

          def sellable_trains(entity)
            entity.trains
          end

          def train_sale_price(train)
            train.salvage
          end

          def process_sell_train(action)
            operator = action.entity
            train = action.train
            raise GameError, "#{operator.name} does not own #{train.name}" unless operator.trains.include?(train)

            @game.sell_train_to_bank(operator, train)
          end
        end
      end
    end
  end
end
