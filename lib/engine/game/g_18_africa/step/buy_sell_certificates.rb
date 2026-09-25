# frozen_string_literal: true

require_relative '../../../step/buy_sell_par_shares'

module Engine
  module Game
    module G18Africa
      module Step
        # Stock Round [2]: selling is only allowed on a player's first turn, then one purchase option:
        #   :hand     any number of cards from hand at printed cost
        #   :pool     a single Share/Private from the Bank Pool (several shares of one company at a Market Value <= 61)
        #   :discard  any number of cards from the top of the Bank Discard, in order
        #   :deck     reveal the top of the Bank Deck and buy it or put it back, up to three times
        #   :bond     a single Government Bond
        # A player who buys nothing has passed and flips the top card of the Bank Deck.
        class BuySellCertificates < Engine::Step::BuySellParShares
          PURCHASE_ACTIONS = [Action::BuyCompany, Action::BuyShares].freeze

          def round_state
            super.merge(turns_taken: Hash.new(0), purchase_mode: nil, deck_card: nil, deck_purchases: 0)
          end

          def setup
            super
            @round.turns_taken[current_entity] += 1 if current_entity
            @round.purchase_mode = nil
            @round.deck_card = nil
            @round.deck_purchases = 0
          end

          def description
            selling_turn?(current_entity) ? 'Sell, then buy Certificates' : 'Buy Certificates'
          end

          def pass_description
            bought? ? 'Done' : 'Pass'
          end

          def actions(entity)
            return [] unless entity == current_entity

            actions = []
            if selling_turn?(entity)
              actions << 'sell_shares' if can_sell_any?(entity)
              actions << 'sell_company' if can_sell_any_companies?(entity)
              return actions if must_sell?(entity) && !actions.empty?
            end
            actions << 'buy_company' unless buyable_companies(entity).empty?
            actions << 'buy_shares' if can_buy_any?(entity)
            actions << 'choose' if choice_available?(entity)
            actions << 'pass' unless actions.empty?
            actions
          end

          def first_stock_round?
            @game.stock_round_number == 1
          end

          def selling_turn?(entity)
            @round.turns_taken[entity] == 1 && !bought? && @round.deck_card.nil?
          end

          # ----- Buying cards (hand, Bank Discard, Bank Deck, Bank Pool privates, Bonds)

          def buyable_companies(entity)
            return [] unless entity&.player?

            mode = @round.purchase_mode
            cards = []
            cards.concat(entity.hand) if [nil, :hand].include?(mode)
            unless first_stock_round?
              cards << @game.top_of_discard if [nil, :discard].include?(mode) && @game.top_of_discard
              cards.concat(@game.bank_deck + @game.bank_discard) if [nil, :face_up].include?(mode) && @game.bank_cards_face_up?
              cards << @round.deck_card if mode == :deck && @round.deck_card
              cards.concat(pool_privates) if mode.nil?
            end
            cards << @game.bonds_in_bank.first if mode.nil? && !@game.bonds_in_bank.empty?
            cards.compact.uniq.select { |card| affordable?(entity, card) }
          end

          def can_buy_company?(entity, company)
            buyable_companies(entity).include?(company)
          end

          def pool_privates
            @game.bank.companies.select { |c| c.type == :private }
          end

          def affordable?(entity, card)
            return false if entity.cash < card.value
            return true if card.type == :bond

            @game.num_certs(entity) < @game.cert_limit(entity)
          end

          def process_buy_company(action)
            entity = action.entity
            card = action.company
            raise GameError, "Cannot buy #{card.name}" unless can_buy_company?(entity, card)

            track_action(action, card)

            if entity.hand.include?(card)
              @round.purchase_mode = :hand
              @game.buy_card(entity, card, 'their hand')
            elsif card.type == :bond
              @round.purchase_mode = :bond
              buy_from_bank(entity, card)
              end_turn!
            elsif pool_privates.include?(card)
              @round.purchase_mode = :pool
              buy_from_bank(entity, card)
              end_turn!
            elsif card == @round.deck_card
              buy_from_deck(entity, card)
            elsif @game.bank_cards_face_up?
              @round.purchase_mode = :face_up
              @game.buy_card(entity, card, 'the Bank')
            else
              @round.purchase_mode = :discard
              @game.buy_card(entity, card, 'the Bank Discard')
              end_turn! if @game.bank_discard.empty?
            end
          end

          def buy_from_bank(entity, card)
            @game.bank.companies.delete(card)
            card.owner = entity
            entity.companies << card
            entity.spend(card.value, @game.bank)
            @log << "#{entity.name} buys #{card.name} from the Bank for #{@game.format_currency(card.value)}"
          end

          def buy_from_deck(entity, card)
            @game.buy_card(entity, card, 'the Bank Deck')
            @round.deck_card = nil
            @round.deck_purchases += 1
            end_turn! if @round.deck_purchases >= @game.class::MAX_DECK_PURCHASES
          end

          # ----- Revealing the Bank Deck

          def choice_available?(entity)
            return false unless entity == current_entity
            return true if @round.deck_card

            can_reveal?(entity)
          end

          def can_reveal?(_entity)
            return false if first_stock_round? || @game.bank_cards_face_up?
            return false unless [nil, :deck].include?(@round.purchase_mode)

            @round.deck_purchases < @game.class::MAX_DECK_PURCHASES && @game.top_of_deck
          end

          def choice_name
            'Bank Deck'
          end

          def choices
            if (card = @round.deck_card)
              { 'decline' => "Put #{card.name} back and end turn" }
            else
              { 'reveal' => 'Reveal the top card of the Bank Deck' }
            end
          end

          def process_choose(action)
            entity = action.entity
            case action.choice
            when 'reveal'
              raise GameError, 'Cannot reveal the Bank Deck' if @round.deck_card || !can_reveal?(entity)

              @round.purchase_mode = :deck
              @round.deck_card = @game.top_of_deck
              @log << "#{entity.name} reveals #{@round.deck_card.name} from the Bank Deck"
            when 'decline'
              raise GameError, 'No revealed card' unless @round.deck_card

              @log << "#{entity.name} puts #{@round.deck_card.name} back"
              @round.deck_card = nil
              end_turn!
            else
              raise GameError, "Unknown choice #{action.choice}"
            end
          end

          # ----- Buying shares from the Bank Pool

          def can_buy_any?(entity)
            return false if first_stock_round?

            can_buy_any_from_market?(entity)
          end

          def can_buy_shares?(entity, shares)
            return false if shares.empty?

            can_buy?(entity, shares.first.to_bundle)
          end

          def can_buy?(entity, bundle)
            return false unless bundle&.buyable
            return false if first_stock_round?
            return false unless bundle.owner == @game.share_pool

            corporation = bundle.corporation
            mode = @round.purchase_mode
            return false if !mode.nil? && (mode != :pool || !multiple_buy?(corporation))
            return false if @round.players_sold[entity][corporation]

            entity.cash >= bundle.price && can_gain?(entity, bundle)
          end

          # Several shares of the same company may be bought at a Market Value of 61 or less
          def multiple_buy?(corporation)
            purchases = @round.current_actions.select { |a| PURCHASE_ACTIONS.include?(a.class) }
            corporation.share_price.price <= @game.class::MULTIPLE_BUY_MAX_PRICE &&
              purchases.all? { |a| a.is_a?(Action::BuyShares) && a.bundle.corporation == corporation }
          end

          def process_buy_shares(action)
            entity = action.entity
            bundle = action.bundle
            raise GameError, "Cannot buy #{bundle.corporation.name} shares" unless can_buy?(entity, bundle)

            @round.purchase_mode = :pool
            @round.players_bought[entity][bundle.corporation] += bundle.percent
            track_action(action, bundle.corporation)
            @game.buy_pool_shares(entity, bundle)
            end_turn! unless multiple_buy?(bundle.corporation)
          end

          # ----- Selling [2.1]

          def can_sell?(entity, bundle)
            return false unless bundle
            return false unless selling_turn?(entity)
            return false if entity != bundle.owner
            # TODO: stage 2: exchange of the Director's Certificate on sale
            return false if bundle.presidents_share

            true
          end

          def must_sell?(entity)
            @game.num_certs(entity) > @game.cert_limit(entity)
          end

          def can_sell_any_companies?(entity)
            !sellable_companies(entity).empty?
          end

          def sellable_companies(entity)
            return [] unless selling_turn?(entity)

            entity.companies.select { |c| %i[private bond].include?(c.type) }
          end

          def sell_price(company)
            company.value
          end

          def process_sell_company(action)
            entity = action.entity
            company = action.company
            raise GameError, "Cannot sell #{company.name}" unless sellable_companies(entity).include?(company)

            entity.companies.delete(company)
            company.owner = @game.bank
            @game.bank.companies << company
            @game.bank.spend(company.value, entity)
            @log << "#{entity.name} sells #{company.name} to the Bank for #{@game.format_currency(company.value)}"
            track_action(action, company)
          end

          # ----- Ending the turn

          def process_pass(_action)
            end_turn!
          end

          def skip!
            end_turn!
          end

          def end_turn!
            entity = current_entity
            if !bought?
              @log << "#{entity.name} passes"
              @game.flip_top_card! unless first_stock_round?
            elsif @round.purchase_mode == :deck || (@round.purchase_mode == :discard && @game.bank_discard.empty?)
              @game.flip_top_card!
            end
            pass!
          end

          def pass!
            @passed = true
            if bought?
              @round.pass_order.delete(current_entity)
              current_entity.unpass!
            else
              @round.pass_order |= [current_entity]
              current_entity.pass!
            end
          end
        end
      end
    end
  end
end
