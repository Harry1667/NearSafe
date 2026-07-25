import Foundation
import MapKit

/// 交給網格演算法的事件快照。
///
/// SwiftData model 留在主執行緒讀取；演算法只使用這裡已擷取的值，
/// 因此分組本身不依賴畫面狀態，也不會跨執行緒讀取 model 欄位。
nonisolated struct EventClusterItem {
    let event: LocalSafetyEvent
    let eventKey: String
    let coordinate: CLLocationCoordinate2D
    let isOfficiallyConfirmed: Bool
    let occurredAt: Date
}

/// 地圖遠距視野中的事件叢集。
nonisolated struct EventCluster: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let count: Int
    let events: [LocalSafetyEvent]
    let hasOfficialConfirmed: Bool
    let latestOccurredAt: Date?
}

/// 依目前鏡頭跨度，以固定網格做一次線性事件聚合。
nonisolated enum EventClustering {
    private struct GridCell: Hashable {
        let latitudeIndex: Int
        let longitudeIndex: Int
    }

    private struct Bucket {
        var items: [EventClusterItem]
        var latitudeSum: Double
        var longitudeSum: Double
        var hasOfficialConfirmed: Bool
        var latestOccurredAt: Date
        var stableEventKey: String
    }

    /// 將事件分配至約 `gridDivisions × gridDivisions` 的畫面網格。
    ///
    /// 網格以全球經緯度原點固定錨定；鏡頭平移但跨度不變時，
    /// 同一事件不會只因畫面中心略微移動就切換格子。
    nonisolated static func cluster(
        items: [EventClusterItem],
        region: MKCoordinateRegion,
        gridDivisions: Int = 8
    ) -> [EventCluster] {
        guard !items.isEmpty else { return [] }

        let divisions = max(gridDivisions, 1)
        let latitudeCellSize = max(abs(region.span.latitudeDelta) / Double(divisions), 0.000_001)
        let longitudeCellSize = max(abs(region.span.longitudeDelta) / Double(divisions), 0.000_001)

        var buckets: [GridCell: Bucket] = [:]
        var insertionOrder: [GridCell] = []
        buckets.reserveCapacity(min(items.count, divisions * divisions))
        insertionOrder.reserveCapacity(min(items.count, divisions * divisions))

        for item in items {
            let coordinate = item.coordinate
            guard CLLocationCoordinate2DIsValid(coordinate),
                  coordinate.latitude.isFinite,
                  coordinate.longitude.isFinite else { continue }

            let cell = GridCell(
                latitudeIndex: Int(floor((coordinate.latitude + 90) / latitudeCellSize)),
                longitudeIndex: Int(floor((coordinate.longitude + 180) / longitudeCellSize))
            )

            if var bucket = buckets[cell] {
                bucket.items.append(item)
                bucket.latitudeSum += coordinate.latitude
                bucket.longitudeSum += coordinate.longitude
                bucket.hasOfficialConfirmed = bucket.hasOfficialConfirmed || item.isOfficiallyConfirmed
                bucket.latestOccurredAt = max(bucket.latestOccurredAt, item.occurredAt)
                bucket.stableEventKey = min(bucket.stableEventKey, item.eventKey)
                buckets[cell] = bucket
            } else {
                insertionOrder.append(cell)
                buckets[cell] = Bucket(
                    items: [item],
                    latitudeSum: coordinate.latitude,
                    longitudeSum: coordinate.longitude,
                    hasOfficialConfirmed: item.isOfficiallyConfirmed,
                    latestOccurredAt: item.occurredAt,
                    stableEventKey: item.eventKey
                )
            }
        }

        return insertionOrder.compactMap { cell in
            guard let bucket = buckets[cell], !bucket.items.isEmpty else { return nil }
            let count = bucket.items.count

            return EventCluster(
                id: "event-cluster-\(bucket.stableEventKey)",
                coordinate: CLLocationCoordinate2D(
                    latitude: bucket.latitudeSum / Double(count),
                    longitude: bucket.longitudeSum / Double(count)
                ),
                count: count,
                events: bucket.items.map(\.event),
                hasOfficialConfirmed: bucket.hasOfficialConfirmed,
                latestOccurredAt: bucket.latestOccurredAt
            )
        }
    }
}
