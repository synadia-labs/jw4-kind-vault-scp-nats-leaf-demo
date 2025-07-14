%{ if username != "" && password != "" ~}
imagePullSecret:
  enabled: true
  username: ${username}
  password: ${password}%{ if image_registry != "" }
  registry: ${image_registry}%{ endif }

%{ endif ~}
container:
  image:%{ if image_repository != "" }
    repository: ${image_repository}%{ endif }%{ if image_tag != "" }
    tag: ${image_tag}%{ endif }%{ if image_pull_policy != "" }
    pullPolicy: ${image_pull_policy}%{ endif }%{ if image_registry != "" }
    registry: ${image_registry}%{ endif }

