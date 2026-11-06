# Вместо заглушки в функции voice():
import google.generativeai as genai

# Настройка ключа (ключ берется из переменной окружения на Render)
genai.configure(api_key=os.environ.get("GEMINI_API_KEY"))
model = genai.GenerativeModel('gemini-pro')

# ... (внутри функции voice(), после получения user_text) ...
try:
    response = model.generate_content(user_text)
    response_text = response.text
except Exception as e:
    logger.error(f"Gemini Error: {e}")
    response_text = "Прости, Хранитель, у меня проблема с доступом к моему мозгу. Попробуй еще раз."
