# frozen_string_literal: true

require 'spec_helper'
require_relative 'spec_helpers'

module Engine
  module Game
    module G18Africa
      describe Game do
        include G18AfricaSpecHelpers

        let(:players) { %w[a b c] }
        # first seed where Marrakech-Fez (home D5, next to Casablanca D3) is in the game
        let(:game) { Engine::Game::G18Africa::Game.new(players, id: seed_with('MF')) }
        let(:mf) { game.corporation_by_id('MF') }

        # MF is started with its Director's Certificate and given enough money for trains
        def start_mf
          reach_first_stock_round
          start_with_director(mf)
          finish_first_stock_round
        end

        def lay_marrakech_towards_casablanca
          lay(mf, 'D5', '115', [3])
        end

        def pass_until(step_class)
          process('pass', current) until step.is_a?(step_class)
        end

        def run_marrakech_casablanca(train)
          pass_until(Engine::Step::Route)
          process('run_routes', mf, routes: [{ 'train' => train.id, 'connections' => [%w[D5 D3]] }])
        end

        it 'lists the Transcontinental Routes in a map legend' do
          _props, header, *rows = game.transcontinental_legend('black', nil, 'green', nil, nil, nil)
          expect(header.first[:text]).to eq('Transcontinental Routes')
          expect(rows.map { |r| r.map { |cell| cell[:text] } }).to eq([
            ['Cairo (N7) ⟷ Cape Town (K36)', '£80'],
            ['Dakar (B11) ⟷ Dar es Salaam (P23)', '£100'],
          ])
        end

        describe 'economy' do
          it 'is Recovery in the first two Operating Rounds regardless of the Bank Pool' do
            start_mf
            expect(game.operating_round_number).to eq(1)
            allow(game).to receive(:bank_pool_certificates).and_return(9)
            expect(game.economy).to eq(:recovery)
          end

          it 'depends on the number of Shares and Privates in the Bank Pool afterwards' do
            allow(game).to receive(:operating_round_number).and_return(3)
            { 0 => :boom, 1 => :recovery, 2 => :recovery, 3 => :recession, 6 => :recession, 7 => :depression }
              .each do |count, economy|
                allow(game).to receive(:bank_pool_certificates).and_return(count)
                expect(game.economy).to eq(economy)
              end
          end

          it 'pays Bonds at the start of an Operating Round' do
            reach_first_stock_round
            player = current
            bond = game.bonds_in_bank.first
            process('buy_company', player, company: bond.id, price: bond.value)
            cash = player.cash
            advance while game.stock_round_number == 1
            # no company started, so both ORs pass immediately: two Recovery payouts of 15
            expect(player.cash).to eq(cash + 30)
          end
        end

        describe 'running trains' do
          before do
            start_mf
            lay_marrakech_towards_casablanca
            pass_until(G18Africa::Step::BuyTrain)
            @train = game.depot.depot_trains.first
            process('buy_train', mf, train: @train.id, price: @train.price)
          end

          it 'allows only one train from the Bank per Operating Round' do
            expect(step.buyable_trains(mf).select { |t| t.owner == game.depot }).to be_empty
          end

          it 'values a Variable City by the best Non-Variable City on the route' do
            process('pass', mf)
            advance until current == mf && game.operating_round_number == 2
            run_marrakech_casablanca(@train)
            # Marrakech 20 + Casablanca (?+20) 40
            expect(step.total_revenue).to eq(60)
          end

          it 'moves the Share Price by the revenue relative to the Market Value' do
            process('pass', mf)
            advance until current == mf && game.operating_round_number == 2
            run_marrakech_casablanca(@train)
            price = mf.share_price.price # 71 after not running in OR 1
            process('dividend', mf, kind: 'payout')
            expect(mf.share_price.price).to be > price
          end

          it 'adds 20 to Cities in a Boom' do
            process('pass', mf)
            advance until current == mf && game.operating_round_number == 2
            run_marrakech_casablanca(@train)
            process('dividend', mf, kind: 'withhold')
            advance while game.operating_round_number == 2
            process('pass', current) while game.round.is_a?(Engine::Round::Stock)
            expect(game.economy).to eq(:boom)
            run_marrakech_casablanca(@train)
            # Marrakech 40 + Casablanca (?+20) 60
            expect(step.total_revenue).to eq(100)
          end

          it 'sells a train back to the Bank for its resale price' do
            cash = mf.cash
            process('sell_train', mf, train: @train.id, price: @train.salvage)
            expect(mf.cash).to eq(cash + 180)
            expect(game.depot.discarded).to include(@train)
          end
        end

        describe 'dividend movement' do
          let(:dividend_step) { G18Africa::Step::Dividend.new(game, game.round) }

          before { start_mf }

          it 'follows the half/double/triple/quadruple thresholds' do
            value = mf.share_price.price
            expect(dividend_step.share_price_change(mf, 0)).to eq(share_direction: :left, share_times: 1)
            expect(dividend_step.share_price_change(mf, (value / 2) - 1)).to eq({})
            expect(dividend_step.share_price_change(mf, value)).to eq(share_direction: :right, share_times: 1)
            expect(dividend_step.share_price_change(mf, 2 * value)).to eq(share_direction: :right, share_times: 2)
            expect(dividend_step.share_price_change(mf, 3 * value)).to eq(share_direction: :right, share_times: 3)
            expect(dividend_step.share_price_change(mf, 5 * value)).to eq(share_direction: :right, share_times: 4)
          end
        end

        describe 'train availability' do
          it 'makes all trains available after the last 4E is bought' do
            depot = game.depot
            buyer = game.corporations.first
            game.bank.spend(20_000 - game.bank.cash, buyer) if game.bank.cash < 20_000
            until depot.upcoming.none? { |t| t.name == '4E' }
              train = depot.upcoming.first
              game.buy_train(buyer, train, :free)
              game.phase.buying_train!(buyer, train, depot)
              buyer.trains.clear
            end
            expect(game.phase.name).to eq('All')
            expect(depot.depot_trains.map(&:name).uniq).to include('3+3', '3+3T', '4+4+4E', '4+4+4T')
          end
        end

        describe 'Managed Company' do
          it 'falls back three spaces without a train' do
            reach_first_stock_round
            player = current
            cards = game.companies.select { |c| c.type == :share && c.id.start_with?('MF_') }.first(3)
            cards.each do |card|
              game.remove_card(card)
              player.hand << card
              process('buy_company', player, company: card.id, price: card.value)
            end
            expect(mf.managed?).to be(true)
            process('pass', current) while game.round.is_a?(Engine::Round::Stock)

            expect(mf.share_price.price).to eq(76)
            advance while current == mf && game.operating_round_number == 1
            # one space for not paying, two more for being Managed without a train: 76 -> 71 -> 67 -> 64
            expect(mf.share_price.price).to eq(64)
          end
        end

        describe 'closing' do
          it 'reduces the certificate limit when a company closes' do
            start_mf
            limit = game.cert_limit
            game.close_corporation(mf)
            expect(game.cert_limit).to be < limit
            expect(game.bank_deck + game.bank_discard + game.players.flat_map(&:hand))
              .not_to(include(have_attributes(id: start_with('MF_'))))
          end
        end
      end
    end
  end
end
