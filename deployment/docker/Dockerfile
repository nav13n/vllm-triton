ARG BASE_IMAGE="nvcr.io/nvidia/tritonserver:24.01-py3"
FROM ${BASE_IMAGE}

# set proxy
ARG http_proxy
ARG https_proxy
ARG no_proxy
ARG PIP_EXTRA_INDEX_URL='https://pypi.org/simple'
ARG PIP_EXTRA_INDEX_TRUSTED_HOST='pypi.org'

# Install vllm backend
ADD requirements.txt .
RUN export http_proxy=$http_proxy && export https_proxy=$http_proxy && no_proxy=$no_proxy \
    && export HTTP_PROXY=$http_proxy && export HTTPS_PROXY=$http_proxy && NO_PROXY=$no_proxy \
    && pip install --no-cache-dir --extra-index-url $PIP_EXTRA_INDEX_URL --trusted-host pypi.org --trusted-host $PIP_EXTRA_INDEX_TRUSTED_HOST -r requirements.txt \
    && unset https_proxy && unset http_proxy && unset no_proxy \
    && unset HTTPS_PROXY && unset HTTP_PROXY && unset NO_PROXY

ADD src/model.py /opt/tritonserver/backends/vllm/
ADD tritonserver/model_repository ./model_repository

CMD ["tritonserver", "--model-repository=./model_repository", "--log-verbose=1"]
