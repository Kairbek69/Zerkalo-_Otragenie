import logging
import os
import time
import uuid

from flask import Flask, jsonify, request
from werkzeug.exceptions import HTTPException

app = Flask(__name__)

app.config["DEBUG"] = False

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s [%(name)s] %(message)s",
)

logger = logging.getLogger("mirror-backend")


@app.before_request
def before_request_logging():
    g.request_id = request.headers.get("X-Request-ID", str(uuid.uuid4()))
    g.request_start_time = time.perf_counter()

    logger.info(
        "Incoming request: id=%s method=%s path=%s remote=%s content_type=%s content_length=%s",
        g.request_id,
        request.method,
        request.path,
        request.remote_addr,
        request.content_type,
        request.content_length,
    )


@app.route("/health", methods=["GET"])
def health_check():
    return jsonify({"status": "ok", "service": "mirror-backend"}), 200


@app.route("/voice", methods=["POST"], strict_slashes=False)
def voice():
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return jsonify({"success": False, "error": "Invalid JSON"}), 400

    user_text = data.get("text")
    if not user_text:
        return jsonify({"success": False, "error": "Missing text"}), 400

    logger.info("Processing voice request: %s", user_text)

    return jsonify({"success": True, "response": f"Эхо: {user_text}"}), 200


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 10000))
    app.run(host="0.0.0.0", port=port)
