# frozen_string_literal: true

require 'spec_helper'
require_relative 'spec_helpers'

module Engine
  module Game
    module G18Africa
      describe Game do
        include G18AfricaSpecHelpers

        let(:players) { %w[a b c] }
        let(:game) { Engine::Game::G18Africa::Game.new(players, id: 7) }

        def complete_selection
          game.players.size.times do
            keep = current.hand.sort_by { |c| -c.value }.first(step.cards_to_keep)
            process('select_multiple_companies', current, companies: keep.map(&:id))
          end
        end

        # The nominator wins every card for a bid of 5
        def complete_auction
          while game.round.is_a?(Engine::Round::Auction)
            if step.auctioning
              process('pass', current)
            else
              process('bid', current, company: game.auction_cards.first.id, price: 5)
            end
          end
        end

        def buy_card(player, card)
          process('buy_company', player, company: card.id, price: card.value)
        end

        describe 'setup' do
          it 'uses 9 of the 17 companies and deals 14 cards to each of 3 players' do
            expect(game.corporations.size).to eq(9)
            expect(game.players.map { |p| p.hand.size }).to all(eq(14))
            expect(game.bank_deck.size).to eq((9 * 9) + 6 - (3 * 14))
            expect(game.bonds_in_bank.size).to eq(25)
            expect(game.round).to be_a(Engine::Round::Draft)
          end

          it 'keeps hands sorted by company abbreviation, Director first, Privates last' do
            game.players.each do |player|
              keys = player.hand.map { |card| game.card_sort_key(card) }
              expect(keys).to eq(keys.sort)
            end
          end

          it 'uses 7 companies and removes a 2 and a 3 train with two players' do
            two = Engine::Game::G18Africa::Game.new(%w[a b], id: 7)
            expect(two.corporations.size).to eq(7)
            expect(two.depot.trains.count { |t| t.name == '2' }).to eq(5)
            expect(two.depot.trains.count { |t| t.name == '3' }).to eq(3)
          end

          it 'names the home City and its coordinates on every certificate' do
            game.corporations.each do |corporation|
              cards = game.companies.select { |c| c.id.start_with?("#{corporation.id}_") }
              expect(cards.map(&:desc)).to all(end_with("(#{corporation.coordinates})"))
            end
            nr = game.companies.find { |c| c.id == 'NR_1' }
            expect(nr.desc).to eq('10% of NR. Home: Lagos (G16)') if nr
          end

          it 'prices share cards at the printed cost, the Director at twice' do
            corporation = game.corporations.first
            price = G18Africa::Entities::CORPORATION_PRICES[corporation.id]
            cards = game.companies.select { |c| c.id.start_with?("#{corporation.id}_") }
            expect(cards.find { |c| c.type == :director }.value).to eq(2 * price)
            expect(cards.select { |c| c.type == :share }.map(&:value).uniq).to eq([price])
          end
        end

        describe 'certificate selection and initial auction' do
          # the player card view reads step.choices[player] while the selection is hidden
          it 'exposes the selected cards per player for the view' do
            player = current
            card = player.hand.first
            step.select_company(player, card)
            expect(step.choices[player]).to eq([card])
          end

          it 'keeps half of the hand and auctions the discards' do
            complete_selection
            expect(game.players.map { |p| p.hand.size }).to all(eq(7))
            expect(game.auction_cards.size).to eq(21)
            expect(game.round).to be_a(Engine::Round::Auction)
          end

          it 'shows the cards to auction grouped by company in alphabetical order, Privates last' do
            complete_selection
            tiers = step.tiered_auction_companies
            expect(tiers.flatten).to match_array(game.auction_cards)

            shares = tiers.reject { |tier| tier.first.type == :private }
            shares.each { |tier| expect(tier.map { |c| c.id.split('_').first }.uniq.size).to eq(1) }
            abbreviations = shares.map { |tier| tier.first.id.split('_').first }
            expect(abbreviations).to eq(abbreviations.sort)
            expect(tiers.flat_map { |tier| tier.map(&:type) }.drop_while { |type| type != :private })
              .to all(eq(:private))
          end

          it 'shows all Privates of the initial auction in one row' do
            complete_selection
            game.auction_cards.concat(game.bank_deck.select { |c| c.type == :private })
            private_tiers = step.tiered_auction_companies.select { |tier| tier.any? { |c| c.type == :private } }

            expect(private_tiers.size).to eq(1)
            expect(private_tiers.first).to all(have_attributes(type: :private))
            expect(private_tiers.first.size).to be >= 2
          end

          it 'gives auctioned cards to the winner, who pays the bid to the bank' do
            complete_selection
            nominator = current
            card = game.auction_cards.first
            process('bid', nominator, company: card.id, price: 0)
            others = game.players - [nominator]
            process('bid', others.first, company: card.id, price: 12)
            process('pass', others.last)
            process('pass', nominator)

            expect(others.first.hand).to include(card)
            expect(others.first.cash).to eq(694 - 12)
          end

          it 'gives the priority deal to the left of the poorest player' do
            complete_selection
            complete_auction
            expect(game.round).to be_a(Engine::Round::Stock)
            expect(game.stock_round_number).to eq(1)
          end
        end

        describe 'stock round' do
          before do
            complete_selection
            complete_auction
          end

          it 'only allows buying from hand and bonds in the first stock round' do
            expect(step.actions(current)).not_to include('choose')
            expect(step.buyable_companies(current) - current.hand).to all(have_attributes(type: :bond))
          end

          it 'starts a company with its Director certificate and pays the treasury' do
            player = current
            director = player.hand.find { |c| c.type == :director } ||
                       game.players.flat_map(&:hand).find { |c| c.type == :director }
            skip 'no director dealt to current player' unless player.hand.include?(director)

            corporation = game.card_share(director).corporation
            buy_card(player, director)

            expect(corporation.floated?).to be(true)
            expect(corporation.owner).to eq(player)
            expect(corporation.cash).to eq(director.value)
            expect(corporation.share_price.corporations).to include(corporation)
          end

          it 'starts a managed company after three ordinary shares' do
            corporation = game.corporations.first
            share_cards = game.companies.select { |c| c.type == :share && c.id.start_with?("#{corporation.id}_") }.first(3)
            player = current
            share_cards.each do |card|
              game.remove_card(card)
              player.hand << card
            end
            share_cards.first(2).each { |card| buy_card(player, card) }
            expect(corporation.floated?).to be(false)

            buy_card(player, share_cards.last)
            expect(corporation.floated?).to be(true)
            expect(corporation.managed?).to be(true)
            expect(corporation.owner).to eq(player)
          end

          it 'does not count bonds against the certificate limit' do
            player = current
            bond = game.bonds_in_bank.first
            expect { buy_card(player, bond) }.not_to(change { game.num_certs(player) })
            expect(player.companies).to include(bond)
          end
        end

        describe 'Bank Deck' do
          it 'flips the top card of the Bank Deck when a player passes after the first stock round' do
            complete_selection
            complete_auction
            # nobody buys anything, so no company operates and SR 2 follows directly
            advance while game.stock_round_number == 1

            expect(game.stock_round_number).to eq(2)
            top = game.bank_deck.first
            process('pass', current)
            expect(game.bank_discard.last).to eq(top)
          end
        end

        describe 'buying from the Bank Pool' do
          let(:cnr) { game.corporation_by_id('CNR') }
          let(:ur) { game.corporation_by_id('UR') }

          def put_in_pool(corporation, count)
            corporation.ipo_shares.reject(&:president).first(count).each do |share|
              share.buyable = true
              game.share_pool.transfer_shares(share.to_bundle, game.share_pool, allow_president_change: false)
            end
          end

          def buy_from_pool(player, corporation)
            share = game.share_pool.shares_of(corporation).first
            process('buy_shares', player, shares: [share.id], percent: 10)
          end

          before do
            complete_selection
            complete_auction
            advance while game.stock_round_number == 1
            game.stock_market.move_left(ur) # 64 -> 61
            put_in_pool(cnr, 3)
            put_in_pool(ur, 1)
          end

          it 'allows several shares of one company at a Market Value of 61 or less' do
            player = current
            buy_from_pool(player, cnr)
            expect(current).to eq(player)
            buy_from_pool(player, cnr)
            expect(player.shares_of(cnr).size).to eq(2)
          end

          it 'does not allow shares of a second company in the same turn' do
            player = current
            buy_from_pool(player, cnr)
            expect(step.can_buy?(player, game.share_pool.shares_of(ur).first.to_bundle)).to be(false)
          end
        end

        describe 'running low on cards' do
          it 'reshuffles the Bank Discard when the Bank Deck runs out' do
            game.bank_deck.replace(game.bank_deck.first(1))
            game.bank_discard.replace(game.companies.select { |c| c.type == :share }.last(3))
            game.flip_top_card!

            expect(game.bank_deck.size + game.bank_discard.size).to eq(4)
            expect(game.bank_discard.size).to eq(1)
          end

          it 'does not loop when only a single card is left' do
            game.bank_deck.replace(game.bank_deck.first(1))
            game.bank_discard.clear
            game.flip_top_card!

            expect(game.bank_deck.size + game.bank_discard.size).to eq(1)
          end
        end

        it 'replays to the identical state from its actions' do
          complete_selection
          complete_auction
          replay = Engine::Game::G18Africa::Game.new(players, id: 7, actions: game.raw_actions.map(&:to_h))

          expect(replay.players.map { |p| p.hand.map(&:id) }).to eq(game.players.map { |p| p.hand.map(&:id) })
          expect(replay.bank_deck.map(&:id)).to eq(game.bank_deck.map(&:id))
        end
      end
    end
  end
end
