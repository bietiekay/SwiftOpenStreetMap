import Quick
import Nimble
import Foundation
import Result
import CBGPromise
import SwiftyJSON
import FutureHTTP

@testable import SwiftOpenStreetMap

class OverpassServiceTest: QuickSpec {
    override func spec() {
        var subject: DefaultOverpassService!
        var httpClient: FakeHTTPClient!

        let baseURL = URL(string: "https://example.com/")!

        beforeEach {
            httpClient = FakeHTTPClient()

            subject = DefaultOverpassService(
                baseURL: baseURL,
                httpClient: httpClient
            )
        }

        describe("query()") {
            var queryFuture: Future<Result<OverpassResponse, OverpassServiceError>>!

            beforeEach {
                queryFuture = subject.query("a query")
            }

            it("makes a POST request to the endpoint") {
                expect(httpClient.requestCallCount) == 1

                let urlRequest = httpClient.requests.first

                expect(urlRequest?.url) == baseURL
                expect(urlRequest?.httpMethod) == "POST"
                expect(urlRequest?.httpBody).toNot(beNil())
                expect(urlRequest?.allHTTPHeaderFields?["Accept"]) == "application/json"

                if let bodyData = urlRequest?.httpBody, let body = String(data: bodyData, encoding: .utf8) {
                    expect(body) == "a query"
                }
            }

            context("when the request succeeds with HTTP 200") {
                let json = JSON([
                    "version": "0.6",
                    "generator": "A Generator",
                    "osm3s": [
                        "timestamp_osm_base": "2017-04-03T00:00:00Z",
                        "copyright": "Copyright whoever",
                    ],
                    "elements": [
                        [
                            "type": "node",
                            "id": 34,
                            "lat": 7.125,
                            "lon": 8.75,
                            "tags": [
                                "a": "tag",
                                "other": "tag"
                            ]
                        ],
                        [
                            "type": "way",
                            "id": 34,
                            "lat": 7.125,
                            "lon": 8.75,
                            "tags": [
                                "a": "tag",
                                "other": "tag"
                            ]
                        ]
                    ]
                ])
                let data = try! json.rawData()
                beforeEach {
                    let promise = httpClient.requestPromises.last
                    let response = HTTPResponse(
                        body: data,
                        status: HTTPStatus.ok,
                        mimeType: "text/text",
                        headers: [:]
                    )
                    promise?.resolve(.success(response))
                }

                it("resolves the future after parsing the json") {
                    expect(queryFuture.value).toNot(beNil())
                    expect(queryFuture.value?.value) == json.overpassResponse
                }
            }

            context("when the request succeeds with HTTP 400") {
                beforeEach {
                    let promise = httpClient.requestPromises.last
                    let response = HTTPResponse(
                        body: "bad query".data(using: .utf8)!,
                        status: HTTPStatus.badRequest,
                        mimeType: "text/text",
                        headers: [:]
                    )
                    promise?.resolve(.success(response))
                }

                it("resolves with a syntax error") {
                    expect(queryFuture.value).toNot(beNil())
                    expect(queryFuture.value?.error) == OverpassServiceError.syntax("a query")
                }
            }

            context("when the request fails with HTTP 429") {
                beforeEach {
                    let promise = httpClient.requestPromises.last
                    let response = HTTPResponse(
                        body: "too many requests".data(using: .utf8)!,
                        status: HTTPStatus.tooManyRequests,
                        mimeType: "text/text",
                        headers: [:]
                    )
                    promise?.resolve(.success(response))
                }

                it("resolves with a multiple requests error") {
                    expect(queryFuture.value).toNot(beNil())
                    expect(queryFuture.value?.error) == OverpassServiceError.multipleRequests
                }
            }

            context("when the request fails with HTTP 504") {
                beforeEach {
                    let promise = httpClient.requestPromises.last
                    let response = HTTPResponse(
                        body: "gateway timeout".data(using: .utf8)!,
                        status: HTTPStatus.gatewayTimeout,
                        mimeType: "text/text",
                        headers: [:]
                    )
                    promise?.resolve(.success(response))
                }

                it("resolves with a load error") {
                    expect(queryFuture.value).toNot(beNil())
                    expect(queryFuture.value?.error) == OverpassServiceError.load
                }
            }

            context("when the request fails") {
                beforeEach {
                    httpClient.requestPromises.last?.resolve(.failure(.unknown))
                }

                it("forwards the error") {
                    expect(queryFuture.value).toNot(beNil())
                    expect(queryFuture.value?.error) == OverpassServiceError.client(.unknown)
                }
            }
        }
    }
}
