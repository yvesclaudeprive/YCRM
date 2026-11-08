import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import PipedriveKit

/// Faux transport : aucune requête réseau réelle dans les tests.
actor MockTransport: HTTPTransport {
    struct Reply {
        let status: Int
        let body: String
    }

    private let replies: [String: Reply]
    private(set) var recorded: [URLRequest] = []

    init(_ replies: [String: Reply]) {
        self.replies = replies
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let key = "\(request.httpMethod ?? "GET") \(request.url?.path ?? "")"
        recorded.append(request)
        // Réponse propre à un paramètre (« GET /api/v2/activities?person_id=200 »), sinon réponse du chemin.
        let items = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems ?? []
        var reply = replies[key] ?? Reply(status: 404, body: #"{"success":false,"error":"not found"}"#)
        for item in items {
            if let specific = replies["\(key)?\(item.name)=\(item.value ?? "")"] {
                reply = specific
                break
            }
        }
        let url = try XCTUnwrap(request.url)
        let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: nil, headerFields: nil))
        return (Data(reply.body.utf8), response)
    }
}

func decode(_ text: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

func query(_ request: URLRequest, _ name: String) -> String? {
    request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
        .queryItems?.first { $0.name == name }?.value
}

let paris = TimeZone(identifier: "Europe/Paris")!

/// Données 100 % fictives : jamais de vraies données client dans le dépôt.
enum Fixtures {
    static let scoreKey = String(repeating: "a", count: 40)

    static let activities = """
    {"success":true,"data":[
      {"id":1,"subject":"Relancer devis","type":"task","due_date":"2026-11-01","due_time":null,"deal_id":100,"person_id":200,"org_id":300,"participants":[{"person_id":200,"primary":true}],"done":false},
      {"id":2,"subject":"Appeler pour le site","type":"important","due_date":"2026-11-06","due_time":"23:30","deal_id":101,"person_id":null,"org_id":null,"participants":[{"person_id":201,"primary":true}],"done":false},
      {"id":3,"subject":"Sans affaire","type":"task","due_date":"2026-11-05","due_time":"","deal_id":null,"person_id":202,"org_id":301,"participants":[],"done":false},
      {"id":4,"subject":"Futur","type":"task","due_date":"2026-11-20","due_time":null,"deal_id":100,"person_id":200,"org_id":300,"participants":[],"done":false}
    ],"additional_data":{"next_cursor":null}}
    """

    static let dealFields = """
    {"success":true,"data":[
      {"field_name":"Titre","field_code":"title","field_type":"varchar","is_custom_field":false},
      {"field_name":"score priorisation","field_code":"\(scoreKey)","field_type":"double","is_custom_field":true}
    ],"additional_data":{"next_cursor":null}}
    """

    static let deals = """
    {"success":true,"data":[
      {"id":100,"title":"Site vitrine","org_id":300,"person_id":200,"custom_fields":{"\(scoreKey)":42.5}},
      {"id":101,"title":"Campagne SEA","org_id":302,"person_id":201,"custom_fields":{"\(scoreKey)":87}}
    ]}
    """

    static let persons = """
    {"success":true,"data":[
      {"id":200,"name":"Alice Test","org_id":300,"phones":[{"label":"work","value":"01 23 45 67 89","primary":false},{"label":"mobile","value":"06 11 22 33 44","primary":true}],"emails":[{"label":"work","value":"alice@example.com","primary":true}]},
      {"id":201,"name":"Bruno Test","org_id":302,"phones":[{"label":"mobile","value":"+33 7 00 00 00 01","primary":true}],"emails":[]},
      {"id":202,"name":"Chloé Test","org_id":301,"phones":[],"emails":[{"label":"work","value":"chloe@example.com","primary":true},{"label":"other","value":"CHLOE@example.com","primary":false}]}
    ]}
    """

    static let organizations = """
    {"success":true,"data":[
      {"id":300,"name":"Entreprise Alpha"},
      {"id":301,"name":"Entreprise Bêta"},
      {"id":302,"name":"Entreprise Gamma"}
    ]}
    """

    static let activityTypes = """
    {"success":true,"data":[
      {"id":1,"name":"Tâche","key_string":"task","active_flag":true},
      {"id":2,"name":"Répondeur ON/OFF","key_string":"rpondeur_onoff","active_flag":true},
      {"id":3,"name":"Répondeur sans message","key_string":"rpondeur_sans_message","active_flag":true}
    ]}
    """

    static let me = """
    {"success":true,"data":{"id":7,"name":"Utilisateur Test","email":"moi@example.com"}}
    """

    static let personMails = """
    {"success":true,"data":[
      {"object":"mailMessage","data":{"id":902,"subject":"Point interne","mail_thread_id":56,"from":[{"email_address":"collegue@example.com"}],"to":[{"email_address":"client@example.com"}],"cc":[]}},
      {"object":"mailMessage","data":{"id":901,"subject":"Copie","mail_thread_id":57,"from":[{"email_address":"moi@example.com"}],"to":[{"email_address":"autre@example.com"}],"cc":[]}},
      {"object":"mailMessage","data":{"id":900,"subject":"Re: Votre projet","mail_thread_id":55,"from":[{"email_address":"Client@Example.com"}],"to":[{"email_address":"moi@example.com"}],"cc":[],"body_url":"?Expires=0","s3_bucket_path":"1-2/abc/1f00000000000abc/body"}}
    ]}
    """

    static let dealNotes = """
    {"success":true,"data":[
      {"id":71,"content":"<p>Client int&eacute;ress&eacute; par le <b>SEA</b>&nbsp;:</p><ul><li>budget 2&#8239;000 €</li><li>d&eacute;marrage janvier</li></ul>","add_time":"2026-11-05 09:15:00","user_id":7,"user":{"name":"Utilisateur Test"}},
      {"id":72,"content":"   ","add_time":"2026-11-04 09:15:00","user_id":7,"user":{"name":"Utilisateur Test"}},
      {"id":74,"content":"<p>Note d'un collègue</p>","add_time":"2026-11-06 09:15:00","user_id":9,"user":{"name":"Collègue Test"}},
      {"id":75,"content":"<a href=\\"https://app.leexi.ai/fr/calls/abc-123\\" target=\\"_blank\\">Appel découverte Alpha (5 novembre à 11:00)</a><p><b>Utilisateurs Leexi:</b><br></p><ul><li><a href=\\"https://app.leexi.ai/fr/users/1\\">Moi Test</a> (<a href=\\"mailto:moi@example.com\\">moi@example.com</a>) - 60.00%</li></ul><p><b>Contacts:</b></p><ul><li>Client Test - 40.00%</li></ul><br><br><b>Résumé de l'appel:</b><h1>Découverte du besoin</h1><p>Le client veut refaire son site.</p>","add_time":"2026-11-05 10:30:00","user_id":9,"user":{"name":"Intégration Leexi"}},
      {"id":76,"content":"<a href=\\"https://app.leexi.ai/fr/calls/def-456\\">Appel d'un collègue</a><p><b>Utilisateurs Leexi:</b></p><ul><li>Collègue (collegue@example.com)</li></ul><b>Résumé de l'appel:</b><p>Sans moi</p>","add_time":"2026-11-04 10:30:00","user_id":9,"user":{"name":"Intégration Leexi"}}
    ]}
    """

    static let personNotes = """
    {"success":true,"data":[
      {"id":71,"content":"<p>Doublon de la note de l'affaire</p>","add_time":"2026-11-05 09:15:00","user":{"name":"Utilisateur Test"}},
      {"id":73,"content":"Appelé, rappeler lundi","add_time":"2026-10-20 16:00:00","user":{"name":"Utilisateur Test"}}
    ]}
    """

    static let dealActivities = """
    {"success":true,"data":[
      {"id":81,"subject":"Call effectué","type":"call_effectue","due_date":"2026-11-06","due_time":"14:00","deal_id":100,"done":true,"owner_id":7,"note":"<p>A d&eacute;croch&eacute;, OK pour un devis</p>"},
      {"id":82,"subject":"Relance","type":"task","due_date":"2026-11-03","due_time":null,"deal_id":100,"done":true,"owner_id":7,"note":""},
      {"id":83,"subject":"Envoyer la proposition","type":"task","due_date":"2026-10-01","due_time":null,"deal_id":100,"done":true,"owner_id":7,"note":"Proposition envoyée"},
      {"id":84,"subject":"Call d'un collègue","type":"call_effectue","due_date":"2026-11-06","due_time":"16:00","deal_id":100,"done":true,"owner_id":9,"note":"Appel du collègue"},
      {"id":85,"subject":"Outbound answered call","type":"aircall_outbound_answered_","due_date":"2026-11-06","due_time":"17:00","deal_id":100,"done":true,"owner_id":7,"note":"Outbound answered call on Test<br>Contact number: +33 6 00 00 00 00<br>Talking time: 00:02:15<br><br>Logged by Test"}
    ]}
    """

    static let threadMails = """
    {"success":true,"data":[
      {"id":901,"message_time":"2026-10-28T18:40:30.000Z","body_url":"https://cdn.example.com/1-2/abc/1e00000000000def/body?Expires=1&Signature=x"},
      {"id":900,"message_time":"2026-11-06T08:34:46.000Z","s3_bucket_path":"1-2/abc/1f00000000000abc/body"}
    ]}
    """
}
