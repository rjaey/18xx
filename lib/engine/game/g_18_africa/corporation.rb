# frozen_string_literal: true

require_relative '../../corporation'

module Engine
  module Game
    module G18Africa
      class Corporation < Engine::Corporation
        attr_accessor :ordinary_shares_bought

        def initialize(**opts)
          super
          @ordinary_shares_bought = 0
        end

        # A Company starts when either its Director's Certificate has been bought
        # or three ordinary shares have been bought, even if sold again since [2.3]
        def floated?
          @floated ||= director_in_play? || @ordinary_shares_bought >= 3
        end

        def director_in_play?
          presidents_share.owner != self
        end

        # Controlled by a Manager while the Director's Certificate is not owned [2.3]
        def managed?
          floated? && !director_in_play?
        end

        # Remembers when each holder reached their current number of shares,
        # used to break ties between potential Managers [2.3]
        def track_holdings(counts, sequence)
          @holdings ||= {}
          @reached_at ||= {}
          counts.each do |holder, count|
            next if @holdings[holder] == count

            @holdings[holder] = count
            @reached_at[holder] = sequence
          end
        end

        def share_holders_reached_at(holder)
          (@reached_at || {})[holder] || Float::INFINITY
        end

        def num_shares_held_by(entity)
          entity.shares_of(self).sum { |s| s.percent / share_percent }
        end
      end
    end
  end
end
