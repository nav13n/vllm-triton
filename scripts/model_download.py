import mlflow 
import os

os.environ['MLFLOW_HTTP_REQUEST_TIMEOUT'] = '7200'

mlflow.set_tracking_uri("http://localhost/mlflow/")


print('downloading artifacts')
for artifact_uri in ["mlflow-artifacts:/<path to dir>"]:
    mlflow.artifacts.download_artifacts(
        artifact_uri = artifact_uri,
        dst_path= "models/"
    ) 
print('download complete')