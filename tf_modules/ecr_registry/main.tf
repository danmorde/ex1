resource "aws_ecr_repository" "foo" {
  name                 = "ex-1-registry"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}