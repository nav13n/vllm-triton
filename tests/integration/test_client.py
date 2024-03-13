import requests, json, time
from transformers import AutoTokenizer

tokenizer = AutoTokenizer.from_pretrained("TheBloke/Nous-Hermes-2-Mixtral-8x7B-DPO-AWQ",
                                          use_auth_token=True)

def chat(prompt:str):
    payload = {"text_input": prompt, "parameters": {"stream": False, "temperature": 0, "max_tokens": 200}}
    headers = {'Content-Type': 'application/json'}
    start = time.perf_counter()
    response = requests.post("http://localhost:8000/v2/models/vllm_model/generate", headers=headers, data=json.dumps(payload))
    generated_text = response.json()["text_output"]
    request_time = time.perf_counter() - start

    return {'tok_count': len(tokenizer.encode(generated_text)),
        'time': request_time,
        'question': prompt,
        'answer': generated_text,
        'note': 'triton-vllm-awq'}

if __name__ == '__main__':
    prompt = "San Francisco is a city in"
    print(f"User: {prompt}\nMixtral: {chat(prompt)['answer']})")