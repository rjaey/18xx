# frozen_string_literal: true

require_relative 'meta'
require_relative 'map'
require_relative 'entities'
require_relative 'corporation'
require_relative 'player'
require_relative 'step/card_selection'
require_relative 'step/initial_auction'
require_relative 'step/buy_sell_certificates'
require_relative '../base'

module Engine
  module Game
    module G18Africa
      class Game < Game::Base
        include_meta(G18Africa::Meta)
        include Entities
        include Map

        attr_reader :bank_deck, :bank_discard, :auction_cards

        PLAYER_CLASS = G18Africa::Player
        CORPORATION_CLASS = G18Africa::Corporation

        CURRENCY_FORMAT_STR = '£%s'
        BANK_CASH = 14_000
        BANKRUPTCY_ALLOWED = false

        STARTING_CASH = { 2 => 782, 3 => 694, 4 => 606, 5 => 518 }.freeze

        # Certificate limits with 0 closed companies; reductions for closures follow in stage 3 [2.4]
        CERT_LIMIT = { 2 => 28, 3 => 24, 4 => 18, 5 => 15 }.freeze

        # Number of companies chosen at random for the game [1.3]
        CORPORATIONS_IN_GAME = { 2 => 7, 3 => 9, 4 => 9, 5 => 9 }.freeze

        # Shares/Privates dealt to each player; half of them are kept [1.3]
        CERTS_DEALT = { 2 => 16, 3 => 14, 4 => 12, 5 => 10 }.freeze

        NUM_BONDS = 25
        BOND_PRICE = 100

        # Multiple shares may be bought from the Bank Pool at or below this Market Value [2.2]
        MULTIPLE_BUY_MAX_PRICE = 61

        # Cards revealed from the Bank Deck in a single purchase [2.2]
        MAX_DECK_PURCHASES = 3

        CAPITALIZATION = :incremental
        HOME_TOKEN_TIMING = :float
        MUST_BUY_TRAIN = :never
        TRACK_RESTRICTION = :permissive

        # Nothing done in the Stock Round affects the Market Value [7]
        SELL_BUY_ORDER = :sell_buy
        SELL_MOVEMENT = :none
        POOL_SHARE_DROP = :none
        SOLD_OUT_INCREASE = false
        MUST_SELL_IN_BLOCKS = false
        MARKET_SHARE_LIMIT = 100

        GAME_END_CHECK = { bank: :current_or, stock_market: :current_or }.freeze

        # Up to four yellow tiles or a single upgrade [3.2]
        TILE_LAYS = [
          { lay: true, upgrade: true },
          { lay: :not_if_upgraded, upgrade: false },
          { lay: :not_if_upgraded, upgrade: false },
          { lay: :not_if_upgraded, upgrade: false },
        ].freeze

        MARKET = [
          %w[0c 5 10 22 34 45 56 58 61p 64p 67p 71p 76p 82p 90p 100p 112 126 142 160 180 205 230 255
             280 300 320 340 360 380 400e 420e 440e 460e],
        ].freeze

        PHASES = [
          { name: '2', train_limit: 2, tiles: %i[yellow green brown gray], operating_rounds: 2 },
          { name: '3', on: '3', train_limit: 2, tiles: %i[yellow green brown gray], operating_rounds: 2 },
          { name: '4E', on: '4E', train_limit: 2, tiles: %i[yellow green brown gray], operating_rounds: 2 },
        ].freeze

        # Towns never count against the distance; only Cities do [3.4.1].
        # TODO: stage 3: 'T' trains may start/end in towns, 3+3T ignores recessions, 4E counts best four stops.
        TRAINS = [
          {
            name: '2',
            distance: [{ 'nodes' => %w[city offboard], 'pay' => 2, 'visit' => 2 },
                       { 'nodes' => ['town'], 'pay' => 99, 'visit' => 99 }],
            price: 180,
            num: 6,
          },
          {
            name: '3',
            distance: [{ 'nodes' => %w[city offboard], 'pay' => 3, 'visit' => 3 },
                       { 'nodes' => ['town'], 'pay' => 99, 'visit' => 99 }],
            price: 300,
            num: 4,
          },
          {
            name: '4E',
            distance: [{ 'nodes' => %w[city offboard town], 'pay' => 4, 'visit' => 99 }],
            price: 450,
            num: 3,
          },
          # TODO: stage 3: available only after the last 4E is bought [3.6.1]
          {
            name: '3+3',
            distance: [{ 'nodes' => %w[city offboard], 'pay' => 3, 'visit' => 3 },
                       { 'nodes' => ['town'], 'pay' => 99, 'visit' => 99 }],
            multiplier: 2,
            price: 700,
            num: 3,
            available_on: '4E',
          },
          {
            name: '3+3T',
            distance: [{ 'nodes' => %w[city offboard], 'pay' => 3, 'visit' => 3 },
                       { 'nodes' => ['town'], 'pay' => 99, 'visit' => 99 }],
            multiplier: 2,
            price: 850,
            num: 3,
            available_on: '4E',
          },
          {
            name: '4+4+4E',
            distance: [{ 'nodes' => %w[city offboard town], 'pay' => 4, 'visit' => 99 }],
            multiplier: 3,
            price: 1000,
            num: 3,
            available_on: '4E',
          },
          {
            name: '4+4+4T',
            distance: [{ 'nodes' => %w[city offboard], 'pay' => 4, 'visit' => 4 },
                       { 'nodes' => ['town'], 'pay' => 99, 'visit' => 99 }],
            multiplier: 3,
            price: 1200,
            num: 3,
            available_on: '4E',
          },
        ].freeze

        # Amount received when selling a train back to the Bank [3.6.3]
        TRAIN_RESALE_PRICES = {
          '2' => 180, '3' => 180, '4E' => 300, '3+3' => 500, '3+3T' => 650, '4+4+4E' => 750, '4+4+4T' => 850
        }.freeze

        def num_trains(train)
          # With two players, remove one '2' and one '3' train [1.2]
          return train[:num] - 1 if @players.size == 2 && %w[2 3].include?(train[:name])

          super
        end

        def setup_preround
          remove_unused_corporations!
          setup_corporation_prices
          create_bonds
          deal_cards
        end

        def setup
          remove_home_reservations(@removals)
        end

        # Shuffle the 17 charters and keep 9 of them (7 with two players) [1.3]
        def remove_unused_corporations!
          keep = CORPORATIONS_IN_GAME[@players.size]
          removed = @corporations.sort_by { rand }.drop(keep)
          removed.each do |corporation|
            @corporations.delete(corporation)
            corporation.close!
            @removals << corporation
          end
          @log << "Companies removed from the game: #{removed.map(&:name).sort.join(', ')}"
        end

        # Starting spaces of removed Companies are not reserved [3.3.1]
        def remove_home_reservations(corporations)
          corporations.each do |corporation|
            hex_by_id(corporation.coordinates).tile.cities.each do |city|
              city.reservations.delete(corporation)
            end
          end
        end

        # Shares are only bought through cards at the printed price; the Share Price
        # marker is placed on the Stock Track when the Company starts [2.3]
        def setup_corporation_prices
          @corporations.each do |corporation|
            price = @stock_market.par_prices.find { |p| p.price == CORPORATION_PRICES[corporation.id] }
            @stock_market.set_par(corporation, price)
            corporation.share_price.corporations.delete(corporation)
            corporation.ipoed = true
            corporation.ipo_shares.each { |share| share.buyable = false }
          end
        end

        def create_bonds
          @bonds = Array.new(NUM_BONDS) do |index|
            Company.new(
              sym: "BOND#{index + 1}",
              name: 'Government Bond',
              value: BOND_PRICE,
              desc: 'Pays out at the start of each Operating Round depending on the Economy. '\
                    'Does not count against the Certificate Limit.',
              type: :bond,
            )
          end
          @bonds.each do |bond|
            bond.owner = @bank
            @bank.companies << bond
          end
          @companies.concat(@bonds)
        end

        # Every share certificate is represented by a card with the same id as the share
        def create_share_cards
          @corporations.flat_map do |corporation|
            corporation.ipo_shares.map do |share|
              director = share.president
              Company.new(
                sym: share.id,
                name: director ? "#{corporation.id} Director" : "#{corporation.id} Share",
                value: CORPORATION_PRICES[corporation.id] * share.percent / 10,
                desc: "#{share.percent}% of #{corporation.name}#{director ? " (Director's Certificate)" : ''}",
                type: director ? :director : :share,
                color: corporation.color,
                text_color: corporation.text_color,
              )
            end
          end
        end

        def deal_cards
          share_cards = create_share_cards
          @companies.concat(share_cards)

          deck = (share_cards + privates).sort_by { rand }
          @players.each { |player| player.hand = deck.shift(CERTS_DEALT[@players.size]) }
          @bank_deck = deck
          @bank_discard = []
          @auction_cards = []
        end

        def privates
          @companies.select { |c| c.type == :private }
        end

        def share_card?(card)
          %i[share director].include?(card.type)
        end

        def card_share(card)
          share_by_id(card.id)
        end

        def bonds_in_bank
          @bank.companies.select { |c| c.type == :bond }
        end

        def num_certs(entity)
          super - entity.companies.count { |c| c.type == :bond }
        end

        # ----- Bank Deck and Bank Discard [2.2.1]

        def top_of_discard
          @bank_discard.last
        end

        def top_of_deck
          reshuffle_discard_into_deck if @bank_deck.empty?
          @bank_deck.first
        end

        def flip_top_card!
          card = top_of_deck
          return unless card

          @bank_deck.delete(card)
          @bank_discard << card
          @log << "#{card.name} is revealed from the Bank Deck onto the Bank Discard"
          reshuffle_discard_into_deck if @bank_deck.empty?
        end

        def reshuffle_discard_into_deck
          return if @bank_discard.empty?

          @log << 'The Bank Deck is empty; the Bank Discard is shuffled to form a new Bank Deck'
          @bank_deck = @bank_discard.sort_by { rand }
          @bank_discard = []
          flip_top_card!
        end

        # With three or fewer cards left in Deck and Discard, all of them are displayed face up [2.2.1]
        def bank_cards_face_up?
          (@bank_deck.size + @bank_discard.size) <= MAX_DECK_PURCHASES
        end

        def remove_card(card)
          @players.each { |p| p.hand.delete(card) }
          @bank_deck.delete(card)
          @bank_discard.delete(card)
          @auction_cards.delete(card)
        end

        # ----- Buying certificates

        def buy_card(player, card, source)
          remove_card(card)
          price = card.value

          @log << "#{player.name} buys #{card.name} from #{source} for #{format_currency(price)}"
          if share_card?(card)
            buy_share_from_card(player, card_share(card), price)
          else
            card.owner = player
            player.companies << card
            player.spend(price, @bank)
            @bank.companies.delete(card)
          end
        end

        # Unless bought from the Bank Pool, the printed cost goes to the Company's Treasury [2.2.2]
        def buy_share_from_card(player, share, price)
          corporation = share.corporation
          was_started = corporation.floated?
          share.buyable = true
          @share_pool.transfer_shares(share.to_bundle, player, spender: player, receiver: corporation, price: price,
                                                               allow_president_change: false)
          corporation.ordinary_shares_bought += 1 unless share.president
          start_corporation(corporation) if !was_started && corporation.floated?
          update_control(corporation, buyer: player)
        end

        # Shares from the Bank Pool cost the Market Value, paid to the Bank [2.2.2]
        def buy_pool_shares(player, bundle)
          corporation = bundle.corporation
          was_started = corporation.floated?
          price = bundle.price
          @share_pool.transfer_shares(bundle, player, spender: player, receiver: @bank, price: price,
                                                      allow_president_change: false)
          corporation.ordinary_shares_bought += bundle.shares.size
          @log << "#{player.name} buys #{bundle.shares.size} share(s) of #{corporation.name} from the Bank Pool "\
                  "for #{format_currency(price)}"
          start_corporation(corporation) if !was_started && corporation.floated?
          update_control(corporation)
        end

        # Selling never moves the Share Price [7]; unstarted Companies sell at the printed price [2.1]
        def sell_shares_and_change_price(bundle, **_kwargs)
          corporation = bundle.corporation
          seller = bundle.owner
          price = bundle.price
          @share_pool.transfer_shares(bundle, @share_pool, spender: @bank, receiver: seller, price: price,
                                                           allow_president_change: false)
          @log << "#{seller.name} sells #{bundle.shares.size} share(s) of #{corporation.name} to the Bank Pool "\
                  "for #{format_currency(price)}"
          update_control(corporation)
        end

        def stock_round_number
          @stock_round_number || 0
        end

        def new_stock_round
          @stock_round_number = stock_round_number + 1
          super
        end

        def start_corporation(corporation)
          @log << "#{corporation.name} starts. Share Price marker placed at #{format_currency(corporation.share_price.price)}"
          # New markers are placed below markers already on the space [2.3]
          corporation.share_price.corporations << corporation
          place_home_token(corporation)
        end

        # ----- Director and Manager [2.3]

        def update_control(corporation, buyer: nil)
          counts = @players.to_h { |p| [p, corporation.num_shares_held_by(p)] }
          @control_checks = (@control_checks || 0) + 1
          corporation.track_holdings(counts, @control_checks)
          return unless corporation.floated?

          if corporation.director_in_play?
            update_director(corporation, counts, buyer)
          else
            update_manager(corporation, counts)
          end
        end

        def update_director(corporation, counts, buyer)
          director_share = corporation.presidents_share
          director = director_share.owner
          previous = corporation.owner

          # The Director's Certificate just entered play: a Manager who has not been surpassed exchanges for it
          if director == buyer && previous&.player? && previous != buyer && counts[previous] >= counts[buyer]
            swap_director(corporation, previous)
            director = previous
          end

          max = counts.values.max
          if counts[director] < max
            new_director = first_clockwise_from(director, counts.select { |_, v| v == max }.keys)
            swap_director(corporation, new_director)
            director = new_director
          end
          set_controller(corporation, director, 'Director')
        end

        def update_manager(corporation, counts)
          manager = corporation.owner if corporation.owner&.player?
          max = counts.values.max
          return set_controller(corporation, manager, 'Manager') if manager && counts[manager] >= max

          candidates = counts.select { |_, v| v == max }.keys
          new_manager =
            if manager
              first_clockwise_from(manager, candidates)
            else
              # The first among tied players to have reached the tied total
              candidates.min_by { |p| corporation.share_holders_reached_at(p) }
            end
          set_controller(corporation, new_manager, 'Manager')
        end

        def swap_director(corporation, new_director)
          @share_pool.change_president(corporation.presidents_share, corporation.presidents_share.owner, new_director)
        end

        def set_controller(corporation, player, title)
          return if corporation.owner == player

          corporation.owner = player
          @log << "#{player.name} becomes the #{title} of #{corporation.name}"
        end

        def first_clockwise_from(player, candidates)
          index = @players.index(player) || 0
          @players.rotate(index + 1).find { |p| candidates.include?(p) }
        end

        # ----- View helpers

        def show_hidden_hand?
          true
        end

        def player_card_rows(player)
          ['Cards in hand', player.hand.size.to_s]
        end

        def hand_companies_for_stock_round
          return [] unless @round.stock?

          player = @round.current_entity
          return [] unless player&.player?

          player.hand.sort_by { |c| [c.type, -c.value, c.name] }
        end

        # The Bank Discard is public information and shown top card first [2]
        def show_ipo_rows?
          true
        end

        def ipo_rows
          [@bank_discard.reverse]
        end

        def ipo_row_title(_row_number)
          "Bank Discard (Bank Deck: #{@bank_deck.size} cards)"
        end

        # Cards other than hand and Bank Discard that can currently be bought
        def buyable_bank_owned_companies
          step = @round.active_step
          if @round.stock? && step.respond_to?(:buyable_companies) && (player = step.current_entity)&.player?
            return step.buyable_companies(player) - player.hand - [top_of_discard]
          end

          @bank.companies.reject { |c| c.type == :bond } + bonds_in_bank.take(1)
        end

        # ----- Rounds

        def init_round
          @log << "-- #{round_description('Certificate Selection', 1)} --"
          @round_counter += 1
          selection_round
        end

        def selection_round
          Engine::Round::Draft.new(self, [G18Africa::Step::CardSelection], reverse_order: false)
        end

        def initial_auction_round
          Engine::Round::Auction.new(self, [G18Africa::Step::InitialAuction])
        end

        def stock_round
          Engine::Round::Stock.new(self, [
            G18Africa::Step::BuySellCertificates,
          ])
        end

        def next_round!
          @round =
            case @round
            when Engine::Round::Draft
              @log << "-- #{round_description('Initial Auction', 1)} --"
              initial_auction_round
            when Engine::Round::Auction
              give_priority_after_auction
              new_stock_round
            else
              return super
            end
        end

        # Priority goes to the player to the left of the player with the least money [1.3]
        def give_priority_after_auction
          least = @players.min_by(&:cash)
          ties = @players.select { |p| p.cash == least.cash }
          poorest = ties.min_by { rand }
          @players.rotate!(@players.index(poorest) + 1)
          @log << "#{@players.first.name} has the Priority Deal"
        end

        def operating_round(round_num)
          Engine::Round::Operating.new(self, [
            Engine::Step::HomeToken,
            Engine::Step::Track,
            Engine::Step::Token,
            Engine::Step::Route,
            Engine::Step::Dividend,
            Engine::Step::BuyTrain,
          ], round_num: round_num)
        end
      end
    end
  end
end
