FROM perl:5-slim

RUN cpanm --notest \
    Moo \
    Path::Tiny \
    Text::Diff \
  && rm -rf ~/.cpanm

COPY lib/ /app/lib/
COPY bin/ /app/bin/

WORKDIR /work

ENTRYPOINT ["perl", "-I/app/lib", "/app/bin/codefork"]
