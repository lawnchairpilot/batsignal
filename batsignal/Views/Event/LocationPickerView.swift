import SwiftUI
import MapKit
import Combine

struct PickedLocation {
    var name: String
    var coordinate: CLLocationCoordinate2D
}

struct LocationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    var onPick: (PickedLocation) -> Void

    @StateObject private var searchModel = LocationSearchModel()
    @StateObject private var locationService = LocationService()
    @State private var position: MapCameraPosition = .automatic
    @State private var selectedFeature: MapFeature? = nil
    @State private var droppedPin: CLLocationCoordinate2D? = nil
    @State private var droppedPinName: String = ""

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                mapLayer
                searchLayer
            }
            .overlay(alignment: .bottom) {
                if droppedPin != nil {
                    nameField
                }
            }
            .navigationTitle(Strings.Event.pickLocationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.Common.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.Common.confirm) {
                        if let coord = droppedPin {
                            let trimmedName = droppedPinName.trimmingCharacters(in: .whitespaces)
                            let name = trimmedName.isEmpty ? Strings.Event.droppedPin : trimmedName
                            onPick(PickedLocation(name: name, coordinate: coord))
                            dismiss()
                        }
                    }
                    .disabled(droppedPin == nil)
                }
            }
            .onAppear {
                locationService.requestPermission()
                locationService.requestCurrentLocation()
            }
            .onChange(of: locationService.currentLocation) { _, loc in
                guard let loc, droppedPin == nil else { return }
                position = .camera(MapCamera(centerCoordinate: loc.coordinate, distance: 5000))
            }
        }
    }

    // MARK: - Subviews

    private var mapLayer: some View {
        MapReader { proxy in
            Map(position: $position, selection: $selectedFeature) {
                if let coord = droppedPin {
                    Marker(droppedPinName.isEmpty ? Strings.Event.droppedPin : droppedPinName, coordinate: coord)
                        .tint(.red)
                }
                UserAnnotation()
            }
            .gesture(
                LongPressGesture(minimumDuration: 0.5)
                    .sequenced(before: DragGesture(minimumDistance: 0))
                    .onEnded { value in
                        if case .second(true, let drag) = value,
                           let location = drag?.location,
                           let coord = proxy.convert(location, from: .local) {
                            selectCustomPin(coord: coord)
                        }
                    }
            )
        }
        .ignoresSafeArea(edges: .bottom)
        .onChange(of: selectedFeature) { _, feature in
            guard let feature else { return }
            droppedPin = feature.coordinate
            droppedPinName = feature.title ?? Strings.Event.selectedPlace
            searchModel.searchText = feature.title ?? ""
            searchModel.results = []
        }
    }

    private var searchLayer: some View {
        VStack(spacing: 0) {
            searchBar
            if !searchModel.results.isEmpty {
                searchResults
            }
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundColor(.secondary)
            TextField(Strings.Event.searchPlaceholder, text: $searchModel.searchText)
                .autocorrectionDisabled()
                .onSubmit { searchModel.search(near: centerCoordinate) }
            if !searchModel.searchText.isEmpty {
                Button(action: {
                    searchModel.searchText = ""
                    searchModel.results = []
                }) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(.regularMaterial)
        .cornerRadius(12)
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var nameField: some View {
        HStack {
            Image(systemName: "pencil").foregroundColor(.secondary)
            TextField(Strings.Event.nameLocationPlaceholder, text: $droppedPinName)
                .autocorrectionDisabled()
        }
        .padding(10)
        .background(.regularMaterial)
        .cornerRadius(12)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var searchResults: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(searchModel.results, id: \.self) { item in
                    searchResultRow(item: item)
                    Divider().padding(.leading, 16)
                }
            }
            .background(.regularMaterial)
            .cornerRadius(12)
            .padding(.horizontal)
        }
        .frame(maxHeight: 240)
    }

    private func searchResultRow(item: MKMapItem) -> some View {
        let name = item.name ?? Strings.Event.unknownPlaceName
        let subtitle = item.addressRepresentations?.fullAddress(includingRegion: false, singleLine: true)
        return Button(action: { selectSearchResult(item) }) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline).bold()
                    .foregroundColor(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Actions

    private func selectSearchResult(_ item: MKMapItem) {
        let coord = item.location.coordinate
        droppedPin = coord
        droppedPinName = item.name ?? Strings.Event.selectedPlace
        position = .camera(MapCamera(centerCoordinate: coord, distance: 1000))
        searchModel.searchText = item.name ?? ""
        searchModel.results = []
        selectedFeature = nil
    }

    private func selectCustomPin(coord: CLLocationCoordinate2D) {
        droppedPin = coord
        droppedPinName = ""
        selectedFeature = nil
        searchModel.searchText = ""
        searchModel.results = []
    }

    private var centerCoordinate: CLLocationCoordinate2D? {
        locationService.currentLocation?.coordinate
    }
}

// MARK: - Supporting types

class LocationSearchModel: ObservableObject {
    @Published var searchText = ""
    @Published var results: [MKMapItem] = []

    func search(near center: CLLocationCoordinate2D?) {
        guard !searchText.isEmpty else { return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchText
        if let center {
            request.region = MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            )
        }
        MKLocalSearch(request: request).start { response, _ in
            DispatchQueue.main.async {
                self.results = response?.mapItems ?? []
            }
        }
    }
}
