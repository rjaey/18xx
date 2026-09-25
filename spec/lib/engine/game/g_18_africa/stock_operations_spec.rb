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

        describe 'final scoring' do
          it 'adds 10% of owned shares and privates and 5% of trains to the share value' do
            # Example from rule 4: market value 300, a private worth 25, shares worth 100 and 112,
            # trains 3+3T (850) and 2 (180)
            set_price(mf, 300)
            private = game.companies.find { |c| c.id == 'P1' }
            private.owner = mf
            mf.companies << private
            allow(mf).to receive(:corporate_shares).and_return([cnr.shares.last, cnr.shares[-2]])
            set_price(cnr, 112) # both shares at 112 to keep the example simple: 224 instead of 212
            trains = game.depot.upcoming.select { |t| %w[3+3T 2].include?(t.name) }.uniq(&:name)
            allow(mf).to receive(:trains).and_return(trains)

            # 300 + (224 + 25) / 10 + (850 + 180) / 20 = 300 + 24.9 + 51.5 = 376.4
            expect(game.final_share_value(mf)).to eq(376)
          end
        end
      end
    end
  end
end
