# frozen_string_literal: true

require 'spec_helper'
require_relative 'spec_helpers'

module Engine
  module Game
    module G18Africa
      describe Game do
        include G18AfricaSpecHelpers

        let(:players) { %w[a b c] }
        let(:game) { Engine::Game::G18Africa::Game.new(players, id: seed_with('MF', 'CNR')) }
        let(:mf) { game.corporation_by_id('MF') }
        let(:cnr) { game.corporation_by_id('CNR') }

        def put_in_pool(corporation, count)
          corporation.ipo_shares.reject(&:president).first(count).each do |share|
            share.buyable = true
            game.share_pool.transfer_shares(share.to_bundle, game.share_pool, allow_president_change: false)
          end
        end

        def price_at(value)
          game.stock_market.market.flatten.compact.find { |p| p.price == value }
        end

        def set_price(corporation, value)
          corporation.share_price.corporations.delete(corporation)
          corporation.share_price = price_at(value)
          price_at(value).corporations << corporation
        end

        describe 'Company stock operations' do
          before do
            reach_first_stock_round
            start_with_director(mf)
            finish_first_stock_round
            put_in_pool(cnr, 3)
            process('pass', current) until step.is_a?(G18Africa::Step::CorporateBuyShares)
          end

          it 'buys several shares of one company at 61 or less and may take control of it' do
            share = game.share_pool.shares_of(cnr).first
            process('corporate_buy_shares', mf, shares: [share.id], percent: 10)
            expect(step).to be_a(G18Africa::Step::CorporateBuyShares)
            share = game.share_pool.shares_of(cnr).first
            process('corporate_buy_shares', mf, shares: [share.id], percent: 10)
            share = game.share_pool.shares_of(cnr).first
            process('corporate_buy_shares', mf, shares: [share.id], percent: 10)

            expect(mf.shares_of(cnr).size).to eq(3)
            # three ordinary shares start CNR, which is now managed by MF
            expect(cnr.floated?).to be(true)
            expect(cnr.owner).to eq(mf)
            expect(cnr.player).to eq(mf.owner)
          end

          it 'may not buy its own shares' do
            put_in_pool(mf, 1)
            bundle = game.share_pool.shares_of(mf).first.to_bundle
            expect(step.can_buy?(mf, bundle)).to be(false)
          end
        end

        describe "selling the Director's Certificate" do
          let(:director_share) { mf.presidents_share }
          let(:ordinary) { mf.ipo_shares.reject(&:president) }

          before do
            reach_first_stock_round
            advance while game.stock_round_number == 1
          end

          def director_bundle(player)
            game.bundles_for_corporation(player, mf).find { |b| b.presidents_share && b.percent == 20 }
          end

          it 'is exchanged with a holder of at least two shares who then holds the most' do
            seller = current
            buyer = game.players.find { |p| p != seller }
            game.buy_share_from_card(seller, director_share, 152)
            game.buy_share_from_card(seller, ordinary[0], 76)
            ordinary[1..3].each { |share| game.buy_share_from_card(buyer, share, 76) }
            expect(mf.owner).to eq(seller) # 3 : 3, the Director is not surpassed

            bundle = director_bundle(seller)
            expect(step.can_sell?(seller, bundle)).to be(true)
            process('sell_shares', seller, shares: bundle.shares.map(&:id), percent: 20)

            expect(mf.presidents_share.owner).to eq(buyer)
            expect(mf.owner).to eq(buyer)
            expect(mf.num_shares_held_by(buyer)).to eq(3)
            expect(mf.num_shares_held_by(seller)).to eq(1)
            expect(game.share_pool.shares_of(mf).size).to eq(2)
          end

          it 'cannot be sold if nobody could take it over' do
            seller = current
            buyer = game.players.find { |p| p != seller }
            game.buy_share_from_card(seller, director_share, 152)
            game.buy_share_from_card(buyer, ordinary[0], 76)

            expect(step.can_sell?(seller, director_bundle(seller))).to be(false)
          end
        end

        describe 'final scoring' do
          def owned_share(price)
            double(corporation: double(share_price: double(price: price)), num_shares: 1)
          end

          it 'follows the example of rule 4 and rounds each addition down' do
            # market value 300, a private worth 25, shares worth 100 and 112, trains 3+3T and 2
            set_price(mf, 300)
            private = game.companies.find { |c| c.id == 'P1' }
            private.owner = mf
            mf.companies << private
            allow(mf).to receive(:corporate_shares).and_return([owned_share(100), owned_share(112)])
            trains = game.depot.upcoming.select { |t| %w[3+3T 2].include?(t.name) }.uniq(&:name)
            allow(mf).to receive(:trains).and_return(trains)

            # 5% of 1030 = 51.5 -> 51; 10% of 237 = 23.7 -> 23; 300 + 51 + 23
            expect(game.final_share_value(mf)).to eq(374)
          end
        end
      end
    end
  end
end
