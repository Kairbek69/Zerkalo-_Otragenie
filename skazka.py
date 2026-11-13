import os
import logging
from telegram import Update
from telegram.ext import Application, CommandHandler, MessageHandler, filters, ContextTypes
import google.generativeai as genai
import requests

# Настройка логов
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Ключи из Render
TELEGRAM_TOKEN = os.environ.get("TELEGRAM_TOKEN")
GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY")
ELEVENLABS_API_KEY = os.environ.get("ELEVENLABS_API_KEY")

# Настройка Gemini
genai.configure(api_key=GEMINI_API_KEY)
model = genai.GenerativeModel('gemini-pro')

# Обработчик команды /start
async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(
        "Привет, Хранитель! 👋\n"
        "Напиши мне имя ребенка и тему (например: «Тимур, динозавры»), "
        "и я создам волшебную сказку."
    )

# Обработчик текста (создание сказки)
async def generate_skazka(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_text = update.message.text
    await update.message.reply_text("🧚‍♂️ Придумываю сказку, подожди немного...")

    try:
        # 1. Генерация текста через Gemini
        prompt = f"Ты — детский писатель. Напиши добрую сказку на ночь по запросу: {user_text}. Сказка должна быть короткой (3-4 абзаца), с хорошим концом."
        response = model.generate_content(prompt)
        story_text = response.text

        # 2. Отправка текста
        await update.message.reply_text(f"✨ Твоя сказка:\n\n{story_text}")

        # 3. Генерация аудио через ElevenLabs
        await update.message.reply_text("🎙 Озвучиваю сказку голосом...")
        
        url = "https://api.elevenlabs.io/v1/text-to-speech/21m00Tcm4TlvDq8ikWAM" # Голос по умолчанию
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
        
        response_audio = requests.post(url, json=data, headers=headers)
        
        if response_audio.status_code == 200:
            with open("skazka.mp3", "wb") as f:
                f.write(response_audio.content)
            
            # Отправка аудио
            with open("skazka.mp3", "rb") as audio:
                await update.message.reply_voice(voice=audio)
            os.remove("skazka.mp3")
        else:
            await update.message.reply_text("Голос временно недоступен, но текст сказки у тебя есть!")

    except Exception as e:
        logger.error(f"Error: {e}")
        await update.message.reply_text("Прости, Хранитель, произошла ошибка. Попробуй еще раз.")

# Главная функция запуска бота
def main():
    app = Application.builder().token(TELEGRAM_TOKEN).build()
    
    app.add_handler(CommandHandler("start", start))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, generate_skazka))
    
    logger.info("Бот запущен!")
    app.run_polling()

if __name__ == "__main__":
    main()
