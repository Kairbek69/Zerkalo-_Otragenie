import os
import logging
import requests
from flask import Flask, request
from telegram import Update
from telegram.ext import Application, CommandHandler, MessageHandler, filters, ContextTypes
import google.generativeai as genai

# --- НАСТРОЙКА ЛОГОВ ---
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# --- НАСТРОЙКА FLASK (чтобы Render видел сайт и не выключал бота) ---
app = Flask(__name__)

@app.route('/')
def health_check():
    return "Zerkalo Skazka Bot is running!", 200

# --- ПОЛУЧЕНИЕ КЛЮЧЕЙ ---
TELEGRAM_TOKEN = os.environ.get("TELEGRAM_TOKEN")
GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY")
ELEVENLABS_API_KEY = os.environ.get("ELEVENLABS_API_KEY")

# --- НАСТРОЙКА GEMINI ---
genai.configure(api_key=GEMINI_API_KEY)
# Используем актуальную модель
model = genai.GenerativeModel('gemini-1.5-flash')

# --- ФУНКЦИИ БОТА ---
async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(
        "Привет! 👋\n"
        "Я — Зеркало. Напиши мне имя ребенка и тему (например: «Тимур, динозавры»), "
        "и я создам волшебную сказку и озвучу её голосом."
    )

async def generate_skazka(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_text = update.message.text
    await update.message.reply_text("🧚‍♂️ Придумываю сказку, подожди 10-15 секунд...")

    try:
        # 1. Генерация текста через Gemini
        prompt = f"Ты — детский писатель. Напиши добрую сказку на ночь по запросу: {user_text}. Сказка должна быть короткой (3-4 абзаца), с хорошим концом. Не используй сложные слова."
        response = model.generate_content(prompt)
        story_text = response.text

        # 2. Отправка текста
        await update.message.reply_text(f"✨ Твоя сказка:\n\n{story_text}")

        # 3. Генерация аудио через ElevenLabs
        await update.message.reply_text("🎙 Озвучиваю сказку голосом...")
        
        # Голос "Rachel" (стандартный)
        url = "https://api.elevenlabs.io/v1/text-to-speech/21m00Tcm4TlvDq8ikWAM" 
        headers = {
            "Accept": "audio/mpeg",
            "Content-Type": "application/json",
            "xi-api-key": ELEVENLABS_API_KEY
        }
        data = {
            "text": story_text,
            "model_id": "eleven_multilingual_v2",
            "voice_settings": {"stability": 0.5, "similarity_boost": 0.5}
        }
        
        response_audio = requests.post(url, json=data, headers=headers, timeout=30)
        
        if response_audio.status_code == 200:
            with open("skazka.mp3", "wb") as f:
                f.write(response_audio.content)
            
            with open("skazka.mp3", "rb") as audio:
                await update.message.reply_voice(voice=audio)
            os.remove("skazka.mp3")
        else:
            logger.error(f"ElevenLabs Error: {response_audio.text}")
            await update.message.reply_text("Голос временно недоступен, но текст сказки у тебя есть!")

    except Exception as e:
        logger.error(f"Error: {e}")
        await update.message.reply_text(f"Прости, произошла ошибка: {e}")

# --- ЗАПУСК БОТА В ФОНЕ ---
def run_bot():
    application = Application.builder().token(TELEGRAM_TOKEN).build()
    application.add_handler(CommandHandler("start", start))
    application.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, generate_skazka))
    
    logger.info("Бот запущен и слушает Telegram!")
    application.run_polling(drop_pending_updates=True)

if __name__ == "__main__":
    # Запускаем бота в отдельном потоке, чтобы Flask мог работать
    import threading
    bot_thread = threading.Thread(target=run_bot)
    bot_thread.start()
    
    # Запускаем Flask (для Render)
    port = int(os.environ.get("PORT", 8080))
    app.run(host='0.0.0.0', port=port)
