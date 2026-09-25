# frozen_string_literal: true

require_relative 'meta'
require_relative 'map'
require_relative 'entities'
require_relative '../base'

module Engine
  module Game
    module G18Africa
      class Game < Game::Base
        include_meta(G18Africa::Meta)
        include Entities
        include Map

        CURRENCY_FORMAT_STR = '£%s'
        BANK_CASH = 14_000
        BANKRUPTCY_ALLOWED = false

        STARTING_CASH = { 2 => 782, 3 => 694, 4 => 606, 5 => 518 }.freeze

        # Certificate limits with 0 closed companies; reductions for closures follow in stage 3 [2.4]
        CERT_LIMIT = { 2 => 28, 3 => 24, 4 => 18, 5 => 15 }.freeze

        # Number of companies chosen at random for the game [1.3]
        CORPORATIONS_IN_GAME = { 2 => 7, 3 => 9, 4 => 9, 5 => 9 }.freeze

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

        # A Company starts once its Director's Certificate is bought [2.3].
        # TODO: stage 2: alternatively after three ordinary shares have been bought.
        def corporation_opts
          { float_percent: 20 }
        end

        def setup_preround
          remove_unused_corporations!
        end

        def setup
          remove_home_reservations(@removals)

          @corporations.each do |corporation|
            price = @stock_market.par_prices.find { |p| p.price == CORPORATION_PRICES[corporation.id] }
            @stock_market.set_par(corporation, price)
            # Shares are bought at the printed price, there is no par action
            corporation.ipoed = true
          end
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

        def init_round
          @log << "-- #{round_description('Stock', 1)} --"
          @round_counter += 1
          stock_round
        end

        def stock_round
          Engine::Round::Stock.new(self, [
            Engine::Step::BuySellParShares,
          ])
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
