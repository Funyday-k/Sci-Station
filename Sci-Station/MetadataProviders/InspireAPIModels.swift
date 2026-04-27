import Foundation

struct InspireResponse: Decodable {
    let metadata: InspireMetadata
}

struct InspireMetadata: Decodable {
    let titles: [InspireTitle]?
    let abstracts: [InspireAbstract]?
    let authors: [InspireAuthor]?
    let arxivEprints: [InspireArxivEprint]?
    let dois: [InspireDOI]?
    let documents: [InspireDocument]?
    let publicationInfo: [InspirePublicationInfo]?
    let inspireCategories: [InspireCategory]?

    enum CodingKeys: String, CodingKey {
        case titles
        case abstracts
        case authors
        case arxivEprints = "arxiv_eprints"
        case dois
        case documents
        case publicationInfo = "publication_info"
        case inspireCategories = "inspire_categories"
    }
}

struct InspireTitle: Decodable { let title: String }
struct InspireAbstract: Decodable { let value: String }
struct InspireAuthor: Decodable { let fullName: String
    enum CodingKeys: String, CodingKey { case fullName = "full_name" }
}
struct InspireArxivEprint: Decodable { let value: String }
struct InspireDOI: Decodable { let value: String }
struct InspireDocument: Decodable { let url: String? }
struct InspirePublicationInfo: Decodable { let year: Int? }
struct InspireCategory: Decodable { let term: String }