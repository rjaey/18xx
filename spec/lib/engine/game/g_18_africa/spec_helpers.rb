# frozen_string_literal: true

module G18AfricaSpecHelpers
  def step
    game.round.active_step
  end

  def current
    step.current_entity
  end

  def process(type, entity, **args)
    action = {
      'type' => type,
      'entity' => entity.id,
      'entity_type' => entity.player? ? 'player' : 'corporation',
    }
    args.each { |k, v| action[k.to_s] = v }
    game.process_action(action)
    raise game.exception if game.exception
  end

  # Everybody keeps the first half of their hand; each nominator wins their card for 0
  def reach_first_stock_round
    game.players.size.times do
      process('select_multiple_companies', current, companies: current.hand.first(step.cards_to_keep).map(&:id))
    end
    while game.round.is_a?(Engine::Round::Auction)
      if step.auctioning
        process('pass', current)
      else
        process('bid', current, company: game.auction_cards.first.id, price: 0)
      end
    end
  end

  # Starts a company in the first Stock Round with its Director's Certificate and funds it
  def start_with_director(corporation, funds: 1000)
    card = game.companies.find { |c| c.id == "#{corporation.id}_0" }
    player = current
    game.remove_card(card)
    player.hand << card
    process('buy_company', player, company: card.id, price: card.value)
    game.bank.spend(funds, corporation) if funds.positive?
  end

  def finish_first_stock_round
    process('pass', current) while game.round.is_a?(Engine::Round::Stock)
  end

  def seed_with(*corporation_ids, players: %w[a b c])
    (1..500).find do |i|
      g = Engine::Game::G18Africa::Game.new(players, id: i)
      corporation_ids.all? { |id| g.corporation_by_id(id) }
    end
  end

  def rotation_for(corporation, hex, tile, exits)
    (0..5).find do |r|
      tile.rotate!(r)
      exits.all? { |e| tile.exits.include?(e) } && step.legal_tile_rotation?(corporation, hex, tile)
    end
  end

  def lay(corporation, hex_id, tile_name, exits)
    hex = game.hex_by_id(hex_id)
    tile = game.tiles.find { |t| t.name == tile_name }
    rotation = rotation_for(corporation, hex, tile, exits)
    raise "no legal rotation of #{tile_name} on #{hex_id} with exits #{exits}" unless rotation

    process('lay_tile', corporation, hex: hex_id, tile: tile.id, rotation: rotation)
  end
end
