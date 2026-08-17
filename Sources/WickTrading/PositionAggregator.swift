import Foundation

/// Reconstructs position sessions from a raw fill list.
///
/// Fills are grouped per symbol + hedge lane (`positionSide`). Inside a lane
/// the signed quantity (BUY positive, SELL negative) is walked chronologically:
/// a session opens when the lane goes flat -> non-zero and closes when it
/// returns to flat. A single oversized fill that crosses zero closes the old
/// session and opens a fresh one on the other side. Still-non-zero lanes end
/// as open positions.
///
/// Quantities arrive as binary doubles, so a decimal-exact full close (e.g.
/// 0.001 + 0.002 - 0.003) can leave a ~1e-18 residue. Without an epsilon
/// that residue either keeps a closed session "open" forever or - worse -
/// flips past zero and spawns a phantom dust session of ~1e-18, which is
/// exactly the "tiny position that should be closed" symptom. Net values are
/// therefore snapped to flat when within `max(1e-12, gross * 1e-9)` of zero,
/// where gross is the lane's accumulated traded quantity.
public enum PositionAggregator {
    public static func aggregate(fills: [TradingFill]) -> [TradingPosition] {
        var lanes: [String: [TradingFill]] = [:]
        for fill in fills where fill.qty > 0 {
            lanes["\(fill.symbol)|\(fill.positionSide)", default: []].append(fill)
        }

        var positions: [TradingPosition] = []
        for (_, laneFills) in lanes {
            positions.append(contentsOf: walkLane(laneFills))
        }
        return positions.sorted { $0.openTime < $1.openTime }
    }

    private static func walkLane(_ fills: [TradingFill]) -> [TradingPosition] {
        let sorted = fills.sorted { ($0.time, $0.id) < ($1.time, $1.id) }

        var positions: [TradingPosition] = []
        var net = 0.0
        /// Total traded quantity in this lane - scales the flatness epsilon.
        var gross = 0.0
        var session: SessionBuilder?

        @inline(__always)
        func snapToFlatIfDust(_ value: Double) -> Double {
            abs(value) <= max(1e-12, gross * 1e-9) ? 0 : value
        }

        for fill in sorted {
            let delta = (fill.side == "BUY" ? 1.0 : -1.0) * fill.qty
            gross += abs(delta)
            guard delta != 0 else { continue }
            let nextNet = snapToFlatIfDust(net + delta)
            if nextNet == net { continue }

            if session == nil {
                // Flat before this fill: it purely opens a new session.
                var fresh = SessionBuilder(
                    symbol: fill.symbol,
                    lane: fill.positionSide,
                    openTime: fill.time,
                    openFillID: fill.id,
                    side: nextNet > 0 ? .long : .short
                )
                fresh.add(entry: fill.price, qty: fill.qty)
                fresh.peakSize = abs(nextNet)
                fresh.absorb(pnl: fill.realizedPnl, commission: fill.commission, asset: fill.commissionAsset)
                session = fresh
                net = nextNet
                continue
            }

            var current = session!
            current.absorb(pnl: fill.realizedPnl, commission: fill.commission, asset: fill.commissionAsset)

            let closesCurrent = net != 0 && (delta.sign != net.sign)
            if closesCurrent {
                let closePortion = min(abs(net), abs(delta))
                current.add(exit: fill.price, qty: closePortion)
            } else {
                current.add(entry: fill.price, qty: abs(delta))
            }

            if nextNet.sign != net.sign && nextNet != 0 {
                // Flip: the closing portion finished the old session; the
                // remainder opens a fresh one on the other side. The fill's
                // realizedPnl/commission belong to the closing side.
                current.closeTime = fill.time
                positions.append(current.build())
                var fresh = SessionBuilder(
                    symbol: fill.symbol,
                    lane: fill.positionSide,
                    openTime: fill.time,
                    openFillID: fill.id,
                    side: nextNet > 0 ? .long : .short
                )
                let openPortion = abs(nextNet)
                fresh.add(entry: fill.price, qty: openPortion)
                fresh.peakSize = openPortion
                session = fresh
                net = nextNet
                continue
            }

            current.peakSize = max(current.peakSize, abs(nextNet))
            if nextNet == 0 {
                current.closeTime = fill.time
                positions.append(current.build())
                session = nil
            } else {
                session = current
            }
            net = nextNet
        }

        if let open = session {
            positions.append(open.build())
        }
        return positions
    }
}

/// Accumulates one in-progress session; `build()` freezes it into a value.
private struct SessionBuilder {
    let symbol: String
    let lane: String
    let openTime: Int64
    let openFillID: Int64
    let side: TradingPositionSide

    var closeTime: Int64?
    var peakSize = 0.0
    var realizedPnl = 0.0
    var entryNotional = 0.0
    var entryQty = 0.0
    var exitNotional = 0.0
    var exitQty = 0.0
    var commissions: [String: Double] = [:]

    mutating func add(entry price: Double, qty: Double) {
        entryNotional += price * qty
        entryQty += qty
    }

    mutating func add(exit price: Double, qty: Double) {
        exitNotional += price * qty
        exitQty += qty
    }

    mutating func absorb(pnl: Double, commission: Double, asset: String) {
        realizedPnl += pnl
        if commission != 0 {
            commissions[asset, default: 0] += commission
        }
    }

    func build() -> TradingPosition {
        TradingPosition(
            id: "\(symbol)|\(lane)|\(openTime)|\(openFillID)",
            symbol: symbol,
            side: side,
            openTime: Date(timeIntervalSince1970: Double(openTime) / 1000),
            closeTime: closeTime.map { Date(timeIntervalSince1970: Double($0) / 1000) },
            entryPrice: entryQty > 0 ? entryNotional / entryQty : 0,
            exitPrice: exitQty > 0 ? exitNotional / exitQty : nil,
            peakSize: peakSize,
            realizedPnl: realizedPnl,
            commissions: commissions
        )
    }
}
