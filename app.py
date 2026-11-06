from flask import Flask, request, jsonify
import os

app = Flask(__name__)

@app.route('/', methods=['GET'])
def home():
    return "Server is running", 200

@app.route('/voice', methods=['POST'])
def handle_voice():
    return jsonify({"status": "success", "text": "Запрос принят"}), 200

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 5000))
    app.run(host='0.0.0.0', port=port)
