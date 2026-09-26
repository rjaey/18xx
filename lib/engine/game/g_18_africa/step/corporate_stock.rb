# frozen_string_literal: true

require_relative '../../../step/corporate_sell_shares'
require_relative '../../../step/corporate_buy_shares'

module Engine
  module Game
    module G18Africa
      module Step
        # Stock operations of a Company [3.7]: first sell any number of Shares/Privates it owns
        # to the Bank Pool, then buy one Share or Private from the Bank Pool (several shares of one
        # company at a Market Value of 61 or less). Never its own shares, never Bonds.
        class CorporateSellShares < Engine::Step::CorporateSellShares
          def actions(entity)
            return [] unless entity == current_entity

            actions = []
            actions << 'corporate_sell_shares' if can_sell_any?(entity)
            actions << 'corporate_sell_company' unless sellable_companies(entity).empty?
            actions << 'pass' unless actions.empty?
            actions
          end

          def description
            'Sell Shares and Privates'
          end

          # A Director's Certificate can only be sold if another holder takes it over [2.1, 3.7]
          def can_sell?(entity, bundle)
            return false unless super
            return true unless bundle.presidents_share

            !@game.director_exchange_target(entity, bundle.corporation, bundle.percent / bundle.corporation.share_percent).nil?
          end

          def sellable_companies(entity)
            entity.companies.select { |c| c.type == :private }
          end

          def process_corporate_sell_company(action)
            entity = action.entity
            company = action.company
            raise GameError, "Cannot sell #{company.name}" unless sellable_companies(entity).include?(company)

            entity.companies.delete(company)
            company.owner = @game.bank
            @game.bank.companies << company
            @game.bank.spend(company.value, entity)
            @log << "#{entity.name} sells #{company.name} to the Bank for #{@game.format_currency(company.value)}"
          end
        end

        class CorporateBuyShares < Engine::Step::CorporateBuyShares
          def actions(entity)
            return [] unless entity == current_entity

            actions = []
            actions << 'corporate_buy_shares' if can_buy_any?(entity)
            actions << 'corporate_buy_company' unless buyable_companies(entity).empty?
            actions << 'pass' unless actions.empty?
            actions
          end

          def description
            'Buy a Share or Private from the Bank Pool'
          end

          def can_buy_any_from_president?(_entity)
            false
          end

          def can_buy?(entity, bundle)
            return false unless bundle&.buyable
            return false unless bundle.owner == @game.share_pool
            return false if entity == bundle.corporation
            return false if bought_company?(entity)

            corporation = bundle.corporation
            if bought?(entity)
              return false unless last_bought(entity) == corporation
              return false if corporation.share_price.price > @game.class::MULTIPLE_BUY_MAX_PRICE
            end

            entity.cash >= bundle.price
          end

          def process_corporate_buy_shares(action)
            entity = action.entity
            bundle = action.bundle
            raise GameError, "Cannot buy #{bundle.corporation.name}" unless can_buy?(entity, bundle)

            @game.buy_pool_shares(entity, bundle)
            @round.corporations_bought[entity] << bundle.corporation
            pass! unless can_buy_any?(entity)
          end

          def buyable_companies(entity)
            return [] if bought?(entity) || bought_company?(entity)

            @game.bank.companies.select { |c| c.type == :private && entity.cash >= c.value }
          end

          def can_buy_company?(entity, company)
            buyable_companies(entity).include?(company)
          end

          def process_corporate_buy_company(action)
            entity = action.entity
            company = action.company
            raise GameError, "Cannot buy #{company.name}" unless can_buy_company?(entity, company)

            @game.bank.companies.delete(company)
            company.owner = entity
            entity.companies << company
            entity.spend(company.value, @game.bank)
            @round.corporations_bought[entity] << company
            @log << "#{entity.name} buys #{company.name} from the Bank for #{@game.format_currency(company.value)}"
            pass!
          end

          def bought_company?(entity)
            @round.corporations_bought[entity].any?(&:company?)
          end

          def bought?(entity)
            @round.corporations_bought[entity].any?(&:corporation?)
          end
        end
      end
    end
  end
end
