// Kundenverwaltung (system_id 4721) - deliberately minimal: plain JDK
// HttpServer + JDBC against PostgreSQL, no framework, no build tool.
// The OTel Java agent (attached via -javaagent, see deployment.yaml)
// auto-instruments the JDBC calls and emits JVM runtime metrics; the
// HTTP layer isn't a framework the agent recognizes, so its root span
// is created manually below (JDBC calls become child spans of it
// automatically via context propagation, since they run within
// span.makeCurrent()).
import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpHandler;
import com.sun.net.httpserver.HttpServer;
import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.api.baggage.Baggage;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.SpanKind;
import io.opentelemetry.api.trace.StatusCode;
import io.opentelemetry.api.trace.Tracer;
import io.opentelemetry.context.Scope;

import java.io.IOException;
import java.net.InetSocketAddress;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.Random;
import java.util.UUID;
import java.util.concurrent.Executors;
import java.util.logging.Level;
import java.util.logging.Logger;

public class Main {
    static final String DB_URL = System.getenv("DB_URL");
    static final String DB_USER = System.getenv("DB_USER");
    static final String DB_PASSWORD = System.getenv("DB_PASSWORD");
    static final Tracer TRACER = GlobalOpenTelemetry.getTracer("kundenverwaltung");
    // java.util.logging, not System.out.println - the OTel Java agent
    // bridges JUL records to OTLP log export automatically, plain
    // stdout wouldn't be captured as telemetry at all.
    static final Logger LOG = Logger.getLogger("kundenverwaltung");

    public static void main(String[] args) throws Exception {
        initDb();

        HttpServer server = HttpServer.create(new InetSocketAddress(8080), 0);
        server.createContext("/customers", new CustomersHandler());
        server.createContext("/health", exchange -> respond(exchange, 200, "ok"));
        server.setExecutor(Executors.newFixedThreadPool(4));
        server.start();
        LOG.info("Kundenverwaltung listening on :8080");

        startTrafficGenerator();
    }

    static void initDb() throws SQLException {
        try (Connection conn = getConnection(); Statement st = conn.createStatement()) {
            st.execute("CREATE TABLE IF NOT EXISTS customers ("
                    + "id SERIAL PRIMARY KEY, name TEXT NOT NULL, email TEXT NOT NULL)");
        }
    }

    static Connection getConnection() throws SQLException {
        return DriverManager.getConnection(DB_URL, DB_USER, DB_PASSWORD);
    }

    static class CustomersHandler implements HttpHandler {
        public void handle(HttpExchange exchange) throws IOException {
            Span span = TRACER.spanBuilder(exchange.getRequestMethod() + " /customers")
                    .setSpanKind(SpanKind.SERVER)
                    .startSpan();
            try (Scope scope = span.makeCurrent()) {
                // schema/core.yaml's correlation.request_id (Baggage Schema,
                // required_for: http-services) - set on Baggage (so it would
                // propagate to any downstream call this handler ever makes,
                // though it doesn't call any other app today) and explicitly
                // on the span attribute + log line, since neither the SDK
                // nor the collector copies Baggage onto attributes
                // automatically - only application code that's actually
                // current can do that.
                String requestId = UUID.randomUUID().toString();
                try (Scope baggageScope = Baggage.current().toBuilder()
                        .put("correlation.request_id", requestId)
                        .build()
                        .makeCurrent()) {
                    span.setAttribute("correlation.request_id", requestId);

                    String method = exchange.getRequestMethod();
                    int status = 200;
                    String body;
                    try {
                        if (method.equals("GET")) {
                            body = listCustomers();
                            LOG.info("Listed customers [correlation.request_id=" + requestId + "]");
                        } else if (method.equals("POST")) {
                            String requestBody = new String(exchange.getRequestBody().readAllBytes());
                            body = createCustomer(requestBody);
                            status = 201;
                            LOG.info("Created customer: " + body + " [correlation.request_id=" + requestId + "]");
                        } else {
                            body = "method not allowed";
                            status = 405;
                        }
                    } catch (Exception e) {
                        span.recordException(e);
                        span.setStatus(StatusCode.ERROR, e.getMessage());
                        body = "error: " + e.getMessage();
                        status = 500;
                        LOG.log(Level.SEVERE, "Request failed [correlation.request_id=" + requestId + "]", e);
                    }
                    respond(exchange, status, body);
                }
            } finally {
                span.end();
            }
        }
    }

    static void respond(HttpExchange exchange, int status, String body) throws IOException {
        byte[] bytes = body.getBytes();
        exchange.getResponseHeaders().add("Content-Type", "application/json");
        exchange.sendResponseHeaders(status, bytes.length);
        exchange.getResponseBody().write(bytes);
        exchange.close();
    }

    static String listCustomers() throws SQLException {
        StringBuilder sb = new StringBuilder("[");
        try (Connection conn = getConnection();
             Statement st = conn.createStatement();
             ResultSet rs = st.executeQuery("SELECT id, name, email FROM customers ORDER BY id")) {
            boolean first = true;
            while (rs.next()) {
                if (!first) sb.append(",");
                first = false;
                sb.append(String.format("{\"id\":%d,\"name\":\"%s\",\"email\":\"%s\"}",
                        rs.getInt("id"), rs.getString("name"), rs.getString("email")));
            }
        }
        return sb.append("]").toString();
    }

    static String createCustomer(String jsonBody) throws SQLException {
        String name = extract(jsonBody, "name");
        String email = extract(jsonBody, "email");
        try (Connection conn = getConnection();
             PreparedStatement ps = conn.prepareStatement(
                     "INSERT INTO customers (name, email) VALUES (?, ?) RETURNING id")) {
            ps.setString(1, name);
            ps.setString(2, email);
            try (ResultSet rs = ps.executeQuery()) {
                rs.next();
                return String.format("{\"id\":%d,\"name\":\"%s\",\"email\":\"%s\"}", rs.getInt(1), name, email);
            }
        }
    }

    // Deliberately not a real JSON library - one dependency (the JDBC
    // driver) is already enough for a demo meant to stay minimal.
    static String extract(String json, String key) {
        int keyIndex = json.indexOf("\"" + key + "\"");
        int colon = json.indexOf(':', keyIndex);
        int start = json.indexOf('"', colon + 1) + 1;
        int end = json.indexOf('"', start);
        return json.substring(start, end);
    }

    static void startTrafficGenerator() {
        String[] names = {"Anna Muster", "Beat Meier", "Clara Weber", "David Keller", "Elena Frei"};
        Random random = new Random();
        Thread thread = new Thread(() -> {
            int counter = 0;
            while (true) {
                try {
                    Thread.sleep(5000);
                } catch (InterruptedException e) {
                    return;
                }
                Span span = TRACER.spanBuilder("traffic-generator tick").startSpan();
                try (Scope scope = span.makeCurrent()) {
                    if (random.nextBoolean()) {
                        createCustomer(String.format("{\"name\":\"%s\",\"email\":\"user%d@example.com\"}",
                                names[random.nextInt(names.length)], counter++));
                    } else {
                        listCustomers();
                    }
                } catch (Exception e) {
                    span.recordException(e);
                    span.setStatus(StatusCode.ERROR, e.getMessage());
                } finally {
                    span.end();
                }
            }
        });
        thread.setDaemon(true);
        thread.start();
    }
}
