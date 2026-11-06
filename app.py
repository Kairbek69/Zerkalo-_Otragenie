from flask import Flask, request, jsonify
import os

app = Flask(__name__)

@app.before_request
def log_request():
    app.logger.info(f"Request: {request.method} {request.path}")

@app.route('/', methods=['GET'])
def home():
    return "Server is running", 200

@app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "ok"}), 200

@app.route('/voice', methods=['POST'], strict_slashes=False)
def handle_voice():
    data = request.get_json(silent=True) or {}
    return jsonify({
        "status": "success",
        "text": "Запрос принят"
    }), 200

@app.errorhandler(404)
def not_found(e):
    app.logger.warning(f"404 Not Found: {request.method} {request.path}")
    return jsonify({
        "status": "error",
        "error": "not_found",
        "method": request.method,
        "path": request.path
    }), 404

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 5000))
    app.run(host='0.0.0.0', port=port)
